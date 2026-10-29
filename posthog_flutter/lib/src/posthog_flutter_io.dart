import 'dart:async';

import 'util/platform_io_stub.dart'
    if (dart.library.io) 'util/platform_io_real.dart';

import 'package:flutter/services.dart';

import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/util/logging.dart';
import 'surveys/models/posthog_display_survey.dart' as models;
import 'surveys/models/survey_callbacks.dart';
import 'error_tracking/dart_exception_processor.dart';
import 'utils/before_send.dart';
import 'utils/capture_utils.dart';
import 'utils/channel_serialization.dart';
import 'utils/event_options.dart';
import 'utils/flutter_version.dart';
import 'utils/property_normalizer.dart';

import 'feature_flag_result.dart';
import 'feature_flags_loaded.dart';
import 'logs/posthog_log_severity.dart';
import 'posthog_config.dart';
import 'posthog_constants.dart';
import 'posthog_event.dart';
import 'posthog_flutter_platform_interface.dart';
import 'posthog_internal_events.dart';

/// An implementation of [PosthogFlutterPlatformInterface] that uses method channels.
class PosthogFlutterIO extends PosthogFlutterPlatformInterface {
  PosthogFlutterIO() {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// The method channel used to interact with the native platform.
  final _methodChannel = const MethodChannel('posthog_flutter');

  OnFeatureFlagsCallback? _onFeatureFlagsCallback;

  PushIdentityProvider? _pushIdentityProvider;

  /// Stored configuration for accessing inAppIncludes and other settings
  PostHogConfig? _config;

  /// Stored beforeSend callbacks for dropping/modifying events
  List<BeforeSendCallback> _beforeSendCallbacks = [];

  /// Builds the event in the native SDK, runs the beforeSend callbacks on
  /// the built event, then has the native SDK send what they return, so the
  /// callbacks see what the SDK adds. [build] holds the `buildEvent`
  /// arguments.
  ///
  /// Returns the native send result (the uuid on the AI lane), or null when
  /// the native SDK skips the event or a callback drops it.
  Future<Object?> _buildRunBeforeSendAndSend(
    Map<String, Object?> build, {
    bool ai = false,
  }) async {
    final built = await _methodChannel.invokeMapMethod<String, Object?>(
      'buildEvent',
      {...build, 'ai': ai},
    );
    final uuid = built?['uuid'];
    if (built == null || uuid is! String) return null;

    Map<String, Object?>? send;
    try {
      final processed = await applyBeforeSend(
        _beforeSendCallbacks,
        _eventFromNative(built),
      );
      if (processed == null) {
        printIfDebug(
            '[PostHog] Event dropped by beforeSend: ${built['event']}');
      } else {
        send = _eventToNative(processed);
      }
    } catch (e) {
      printIfDebug('[PostHog] Event dropped, it could not be read: $e');
    }
    if (send == null) {
      await _methodChannel.invokeMethod('discardBuiltEvent', {'uuid': uuid});
      return null;
    }
    return _methodChannel.invokeMethod<Object?>(
      'sendBuiltEvent',
      {...send, 'uuid': uuid, 'ai': ai},
    );
  }

  static PostHogEvent _eventFromNative(Map<String, Object?> built) {
    final properties = _stringKeyedMap(built['properties']) ?? {};
    final userProperties = _stringKeyedMap(properties.remove(r'$set'));
    final userPropertiesSetOnce =
        _stringKeyedMap(properties.remove(r'$set_once'));
    final timestampMs = built['timestamp'] as int?;
    return PostHogEvent(
      event: built['event'] as String? ?? '',
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
      options: (built['options'] as Map?)?.cast<String, Object?>(),
      uuid: built['uuid'] as String?,
      distinctId: built['distinctId'] as String?,
      timestamp: timestampMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
    );
  }

  static Map<String, Object?> _eventToNative(PostHogEvent event) {
    final extracted = CaptureUtils.extractUserProperties(
      properties: event.properties,
      userProperties: event.userProperties,
      userPropertiesSetOnce: event.userPropertiesSetOnce,
    );
    final properties = <String, Object>{
      ...?extracted.properties,
      if (extracted.userProperties != null) r'$set': extracted.userProperties!,
      if (extracted.userPropertiesSetOnce != null)
        r'$set_once': extracted.userPropertiesSetOnce!,
    };
    return {
      'event': event.event,
      'properties': PropertyNormalizer.normalize(properties),
      if (event.distinctId?.trim().isNotEmpty == true)
        'distinctId': event.distinctId,
      if (event.timestamp != null)
        'timestamp': event.timestamp!.millisecondsSinceEpoch,
      'options': cleanEventOptions(event.options) ?? const <String, Object?>{},
    };
  }

  /// Copies a map from the channel with its string keys and non-null values.
  static Map<String, Object>? _stringKeyedMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value != null)
          entry.key as String: entry.value as Object,
    };
  }

  /// Native plugin calls to Flutter
  ///
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'showSurvey':
        final survey = Map<String, dynamic>.from(call.arguments);
        return showSurvey(survey);
      case 'hideSurveys':
        await cleanupSurveys();
        return null;
      case 'onFeatureFlagsCallback':
        _onFeatureFlagsCallback
            ?.call(featureFlagsLoadedFromMap(call.arguments));
        break;
      case 'pushIdentityProvider':
        // Returning a value here is the reply the native SDK awaits.
        final provider = _pushIdentityProvider;
        if (provider == null) {
          printIfDebug(
              'pushIdentityProvider invoked but no provider is configured; push subscription will be sent unauthenticated.');
          return null;
        }
        try {
          final arguments = Map<String, Object?>.from(call.arguments as Map);
          return await provider(
            arguments['distinctId'] as String? ?? '',
            arguments['appId'] as String? ?? '',
          );
        } catch (exception) {
          printIfDebug('Exception on pushIdentityProvider: $exception');
          return null;
        }
      case 'onNativeOcclusionChanged':
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        PostHogInternalEvents.nativeOcclusionActive =
            arguments['occluded'] == true;
        PostHogInternalEvents.nativeOcclusionEpisode =
            arguments['episode'] as int? ?? 0;
        PostHogInternalEvents.nativeBridgeFailed =
            arguments['bridgeFailed'] == true;
        PostHogInternalEvents.nativeOcclusionEvent.value++;
        break;
      default:
        printIfDebug(
          '[PostHog] ${call.method} not implemented in PosthogFlutterPlatformInterface',
        );
        return null;
    }
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    if (!isSupportedPlatform()) {
      printIfDebug('Cannot show survey: Platform is not supported');
      return;
    }

    final widget = PosthogFlutterPlatformInterface.instance;
    if (widget is! PosthogFlutterIO) {
      printIfDebug(
        'Cannot show survey: PosthogFlutterPlatformInterface instance is not PosthogFlutterIO',
      );
      return;
    }

    final displaySurvey = models.PostHogDisplaySurvey.fromDict(survey);

    // Try to show using SurveyService
    // This will work if the user has set up the PosthogObserver correctly in their app
    await SurveyService().showSurvey(
      displaySurvey,
      (survey) async {
        // onShown
        try {
          await _methodChannel.invokeMethod('surveyAction', {
            'type': 'shown',
            'presentationId': survey.presentationId,
          });
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(shown): $exception');
        }
      },
      (survey, index, response) async {
        // onResponse
        try {
          final result = await _methodChannel.invokeMethod('surveyAction', {
            'type': 'response',
            'presentationId': survey.presentationId,
            'index': index,
            'response': response,
          }) as Map?;
          if (result == null) return null;
          return PostHogSurveyNextQuestion(
            questionIndex: (result['nextIndex'] as num).toInt(),
            isSurveyCompleted: result['isSurveyCompleted'] as bool,
          );
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(response): $exception');
          if (exception.code == 'SurveyInvalidated') {
            SurveyService().hideSurvey(survey: survey);
          }
        }

        return null;
      },
      (survey) async {
        // onClose
        try {
          await _methodChannel.invokeMethod('surveyAction', {
            'type': 'closed',
            'presentationId': survey.presentationId,
          });
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(closed): $exception');
        }
      },
    );
  }

  /// Cleans up any active surveys when the survey feature is stopped
  Future<void> cleanupSurveys() async {
    if (!isSupportedPlatform()) {
      printIfDebug('Cannot cleanup surveys: Platform is not supported');
      return;
    }

    SurveyService().hideSurvey();
  }

  /// Flutter to Native Calls
  ///
  @override
  Future<void> setup(PostHogConfig config) async {
    // Store config for later use in exception processing
    _config = config;

    if (!isSupportedPlatform()) {
      return;
    }

    _onFeatureFlagsCallback = config.onFeatureFlags;
    _pushIdentityProvider = config.pushIdentityProvider;
    _beforeSendCallbacks = config.beforeSend;

    try {
      await _methodChannel.invokeMethod('setup', {
        ...config.toMap(),
        ...flutterVersionSetupArguments(),
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on setup: $exception');
    }
  }

  @override
  Future<void> setCaptureNativeScreens(bool enabled) async {
    if (!isSupportedPlatform()) {
      return;
    }
    try {
      await _methodChannel.invokeMethod(
        'setCaptureNativeScreens',
        {'enabled': enabled},
      );
    } on PlatformException catch (exception) {
      printIfDebug('Exception on setCaptureNativeScreens: $exception');
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final cleanedOptions = cleanEventOptions(options);
      final normalizedUserProperties = userProperties != null
          ? PropertyNormalizer.normalize(userProperties)
          : null;
      final normalizedUserPropertiesSetOnce = userPropertiesSetOnce != null
          ? PropertyNormalizer.normalize(userPropertiesSetOnce)
          : null;

      await _methodChannel.invokeMethod('identify', {
        'userId': userId,
        if (normalizedUserProperties != null)
          'userProperties': normalizedUserProperties,
        if (normalizedUserPropertiesSetOnce != null)
          'userPropertiesSetOnce': normalizedUserPropertiesSetOnce,
        if (cleanedOptions != null) 'options': cleanedOptions,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on identify: $exception');
    }
  }

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
    Map<String, Object?>? options,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final cleanedOptions = cleanEventOptions(options);
      final normalizedUserPropertiesToSet = userPropertiesToSet != null
          ? PropertyNormalizer.normalize(userPropertiesToSet)
          : null;
      final normalizedUserPropertiesToSetOnce = userPropertiesToSetOnce != null
          ? PropertyNormalizer.normalize(userPropertiesToSetOnce)
          : null;

      await _methodChannel.invokeMethod('setPersonProperties', {
        if (normalizedUserPropertiesToSet != null)
          'userPropertiesToSet': normalizedUserPropertiesToSet,
        if (normalizedUserPropertiesToSetOnce != null)
          'userPropertiesToSetOnce': normalizedUserPropertiesToSetOnce,
        if (cleanedOptions != null) 'options': cleanedOptions,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on setPersonProperties: $exception');
    }
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    await _captureEvent(
      'capture',
      eventName: eventName,
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
      options: options,
    );
  }

  @override
  Future<String?> captureAi({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    final uuid = await _captureEvent(
      'captureAi',
      eventName: eventName,
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
      options: options,
    );
    return uuid is String ? uuid : null;
  }

  /// Runs beforeSend and sends the event through [method], `capture` or
  /// `captureAi`. Returns what the native SDK returned, or null when the
  /// event was dropped.
  Future<Object?> _captureEvent(
    String method, {
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    if (!isSupportedPlatform()) {
      return null;
    }

    if (_beforeSendCallbacks.isNotEmpty) {
      try {
        return await _buildRunBeforeSendAndSend(
          _captureArguments(
            eventName: eventName,
            properties: properties,
            userProperties: userProperties,
            userPropertiesSetOnce: userPropertiesSetOnce,
            options: options,
          ),
          ai: method == 'captureAi',
        );
      } on PlatformException catch (exception) {
        printIfDebug('Exeption on $method: $exception');
        return null;
      }
    }

    try {
      return await _methodChannel.invokeMethod<Object?>(
        method,
        _captureArguments(
          eventName: eventName,
          properties: properties,
          userProperties: userProperties,
          userPropertiesSetOnce: userPropertiesSetOnce,
          options: options,
        ),
      );
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on $method: $exception');
      return null;
    }
  }

  /// The `capture`, `captureAi` and `buildEvent` arguments, with `$set` and
  /// `$set_once` moved out of [properties] and the values normalized.
  static Map<String, Object?> _captureArguments({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) {
    final extracted = CaptureUtils.extractUserProperties(
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );
    final extractedProperties = extracted.properties;
    final extractedUserProperties = extracted.userProperties;
    final extractedUserPropertiesSetOnce = extracted.userPropertiesSetOnce;
    final cleanedOptions = cleanEventOptions(options);
    return {
      'eventName': eventName,
      if (extractedProperties != null)
        'properties': PropertyNormalizer.normalize(extractedProperties),
      if (extractedUserProperties != null)
        'userProperties': PropertyNormalizer.normalize(extractedUserProperties),
      if (extractedUserPropertiesSetOnce != null)
        'userPropertiesSetOnce':
            PropertyNormalizer.normalize(extractedUserPropertiesSetOnce),
      if (cleanedOptions != null) 'options': cleanedOptions,
    };
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
    Map<String, Object?>? options,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    if (_beforeSendCallbacks.isNotEmpty) {
      try {
        final cleanedOptions = cleanEventOptions(options);
        await _buildRunBeforeSendAndSend({
          'eventName': PostHogEventName.screen,
          // The screen name argument wins over a properties `$screen_name`.
          'properties': PropertyNormalizer.normalize({
            ...?properties,
            PostHogPropertyName.screenName: screenName,
          }),
          if (cleanedOptions != null) 'options': cleanedOptions,
        });
      } on PlatformException catch (exception) {
        printIfDebug('Exeption on screen: $exception');
      }
      return;
    }

    try {
      // The native SDK adds the screen name back as `$screen_name`.
      final screenProperties = <String, Object>{...?properties}
        ..remove(PostHogPropertyName.screenName);
      final cleanedOptions = cleanEventOptions(options);

      await _methodChannel.invokeMethod('screen', {
        'screenName': screenName,
        if (screenProperties.isNotEmpty)
          'properties': PropertyNormalizer.normalize(screenProperties),
        if (cleanedOptions != null) 'options': cleanedOptions,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on screen: $exception');
    }
  }

  @override
  Future<void> captureLog({
    required String body,
    PostHogLogSeverity level = PostHogLogSeverity.info,
    Map<String, Object>? attributes,
    String? traceId,
    String? spanId,
    int? traceFlags,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final normalizedAttributes =
          attributes != null ? PropertyNormalizer.normalize(attributes) : null;

      // Trace fields are camelCase here; the web handler remaps them to
      // snake_case for posthog-js.
      await _methodChannel.invokeMethod('captureLog', {
        'body': body,
        'level': level.name,
        if (normalizedAttributes != null) 'attributes': normalizedAttributes,
        if (traceId != null) 'traceId': traceId,
        if (spanId != null) 'spanId': spanId,
        // traceFlags 0 is meaningful (W3C sampled-false); only omit when null.
        if (traceFlags != null) 'traceFlags': traceFlags,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on captureLog: $exception');
    }
  }

  @override
  Future<void> alias({
    required String alias,
    Map<String, Object?>? options,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final cleanedOptions = cleanEventOptions(options);
      await _methodChannel.invokeMethod('alias', {
        'alias': alias,
        if (cleanedOptions != null) 'options': cleanedOptions,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on alias: $exception');
    }
  }

  @override
  Future<void> captureFeatureView({
    required String flag,
    String? flagVariant,
  }) =>
      _invokeFeatureEvent('captureFeatureView', flag, flagVariant);

  @override
  Future<void> captureFeatureInteraction({
    required String flag,
    String? flagVariant,
  }) =>
      _invokeFeatureEvent('captureFeatureInteraction', flag, flagVariant);

  Future<void> _invokeFeatureEvent(
    String method,
    String flag,
    String? flagVariant,
  ) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod(method, {
        'flag': flag,
        if (flagVariant != null) 'flagVariant': flagVariant,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on $method: $exception');
    }
  }

  @override
  Future<String> getDistinctId() async {
    if (!isSupportedPlatform()) {
      return "";
    }

    try {
      return await _methodChannel.invokeMethod('distinctId');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on getDistinctId: $exception');
      return "";
    }
  }

  @override
  Future<void> reset() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('reset');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on reset: $exception');
    }
  }

  @override
  Future<void> optOut() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('disable');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on disable: $exception');
    }
  }

  @override
  Future<void> optIn() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('enable');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on enable: $exception');
    }
  }

  @override
  Future<bool> isOptOut() async {
    if (!isSupportedPlatform()) {
      return true;
    }

    try {
      final result = await _methodChannel.invokeMethod('isOptOut');
      return result as bool? ?? true;
    } on PlatformException catch (exception) {
      printIfDebug('Exception on isOptOut: $exception');
      return true;
    }
  }

  @override
  Future<void> debug(bool enabled) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('debug', {'debug': enabled});
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on debug: $exception');
    }
  }

  @override
  Future<bool> isFeatureEnabled(String key,
      {bool? sendFeatureFlagEvent}) async {
    if (!isSupportedPlatform()) {
      return false;
    }

    try {
      return await _methodChannel.invokeMethod('isFeatureEnabled', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on isFeatureEnabled: $exception');
      return false;
    }
  }

  @override
  Future<PostHogFeatureFlagsLoaded> reloadFeatureFlags() async {
    if (!isSupportedPlatform()) {
      return featureFlagsLoadedFromMap(null);
    }

    try {
      return featureFlagsLoadedFromMap(
          await _methodChannel.invokeMethod('reloadFeatureFlags'));
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on reloadFeatureFlags: $exception');
      return featureFlagsLoadedFromMap(null);
    }
  }

  @override
  Future<void> setPersonPropertiesForFlags(
    Map<String, Object> userProperties,
  ) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final normalizedUserProperties =
          PropertyNormalizer.normalize(userProperties);

      await _methodChannel.invokeMethod('setPersonPropertiesForFlags', {
        'userProperties': normalizedUserProperties,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on setPersonPropertiesForFlags: $exception');
    }
  }

  @override
  Future<void> resetPersonPropertiesForFlags() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('resetPersonPropertiesForFlags');
    } on PlatformException catch (exception) {
      printIfDebug('Exception on resetPersonPropertiesForFlags: $exception');
    }
  }

  @override
  Future<void> setGroupPropertiesForFlags(
    String groupType,
    Map<String, Object> groupProperties,
  ) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final normalizedGroupProperties =
          PropertyNormalizer.normalize(groupProperties);

      await _methodChannel.invokeMethod('setGroupPropertiesForFlags', {
        'groupType': groupType,
        'groupProperties': normalizedGroupProperties,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on setGroupPropertiesForFlags: $exception');
    }
  }

  @override
  Future<void> resetGroupPropertiesForFlags({String? groupType}) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('resetGroupPropertiesForFlags', {
        if (groupType != null) 'groupType': groupType,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on resetGroupPropertiesForFlags: $exception');
    }
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
    Map<String, Object?>? options,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final cleanedOptions = cleanEventOptions(options);
      final normalizedGroupProperties = groupProperties != null
          ? PropertyNormalizer.normalize(groupProperties)
          : null;

      await _methodChannel.invokeMethod('group', {
        'groupType': groupType,
        'groupKey': groupKey,
        if (normalizedGroupProperties != null)
          'groupProperties': normalizedGroupProperties,
        if (cleanedOptions != null) 'options': cleanedOptions,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on group: $exception');
    }
  }

  @override
  Future<Object?> getFeatureFlag({
    required String key,
    bool? sendFeatureFlagEvent,
  }) async {
    if (!isSupportedPlatform()) {
      return null;
    }

    try {
      return await _methodChannel.invokeMethod('getFeatureFlag', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on getFeatureFlag: $exception');
      return null;
    }
  }

  @override
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool? sendFeatureFlagEvent,
  }) async {
    if (!isSupportedPlatform()) {
      return null;
    }

    try {
      final result = await _methodChannel.invokeMethod('getFeatureFlagResult', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      });

      // Native returns: { key, enabled, variant, payload }
      return featureFlagResultFromMap(result, key);
    } on PlatformException catch (exception) {
      printIfDebug('Exception on getFeatureFlagResult: $exception');
      return null;
    }
  }

  @override
  Future<List<PostHogFeatureFlagResult>?> getAllFeatureFlags() async {
    if (!isSupportedPlatform()) {
      return null;
    }

    try {
      final results = await _methodChannel
          .invokeMethod<List<Object?>>('getAllFeatureFlags');
      return results
          ?.map((result) => featureFlagResultFromMap(result, ''))
          .nonNulls
          .toList();
    } on PlatformException catch (exception) {
      printIfDebug('Exception on getAllFeatureFlags: $exception');
      return null;
    }
  }

  @override
  Future<void> register(String key, Object value) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel.invokeMethod('register', {
        'key': key,
        'value': value,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on register: $exception');
    }
  }

  @override
  Future<void> unregister(String key) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel.invokeMethod('unregister', {'key': key});
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on unregister: $exception');
    }
  }

  @override
  Future<void> flush() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel.invokeMethod('flush');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on flush: $exception');
    }
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
    Map<String, Object?>? options,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final exceptionProps = DartExceptionProcessor.processException(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
        inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
        inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
        inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
      );

      if (_beforeSendCallbacks.isNotEmpty) {
        final cleanedOptions = cleanEventOptions(options);
        await _buildRunBeforeSendAndSend({
          'eventName': PostHogEventName.exception,
          'properties': PropertyNormalizer.normalize(
            exceptionProps.cast<String, Object>(),
          ),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (cleanedOptions != null) 'options': cleanedOptions,
        });
        return;
      }

      // Add timestamp from Flutter side (will be used and removed from native plugins)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final normalizedData = PropertyNormalizer.normalize(
        exceptionProps.cast<String, Object>(),
      );
      final cleanedOptions = cleanEventOptions(options);

      await _methodChannel.invokeMethod('captureException', {
        'timestamp': timestamp,
        'properties': normalizedData,
        if (cleanedOptions != null) 'options': cleanedOptions,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception in captureException: $exception');
    }
  }

  @override
  Future<void> addExceptionStep(
    String message, {
    Map<String, Object>? properties,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      final normalizedProperties =
          properties != null ? PropertyNormalizer.normalize(properties) : null;

      await _methodChannel.invokeMethod('addExceptionStep', {
        'message': message,
        if (normalizedProperties != null) 'properties': normalizedProperties,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on addExceptionStep: $exception');
    }
  }

  @override
  Future<void> close() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel.invokeMethod('close');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on close: $exception');
    }
  }

  @override
  Future<String?> getSessionId() async {
    if (!isSupportedPlatform()) {
      return null;
    }

    try {
      final sessionId = await _methodChannel.invokeMethod('getSessionId');
      return sessionId;
    } on PlatformException catch (exception) {
      printIfDebug('Exception on getSessionId: $exception');
      return null;
    }
  }

  // For internal use
  @override
  Future<void> openUrl(String url) async {
    if (!isSupportedPlatform()) {
      printIfDebug('Cannot open url $url: Platform is not supported');
      return;
    }

    try {
      await _methodChannel.invokeMethod('openUrl', url);
    } on PlatformException catch (exception) {
      printIfDebug('Exception on openUrl: $exception');
    }
  }

  @override
  Future<void> registerPushNotificationToken(
    String deviceToken, {
    String? appId,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }
    if (isMacOS()) {
      // The native macOS handler is a no-op (posthog-ios push is iOS-only).
      printIfDebug(
          'registerPushNotificationToken is not supported on macOS; token not registered.');
      return;
    }

    try {
      await _methodChannel.invokeMethod('registerPushNotificationToken', {
        'deviceToken': deviceToken,
        if (appId != null) 'appId': appId,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on registerPushNotificationToken: $exception');
    }
  }

  @override
  Future<void> unregisterPushNotificationToken() async {
    if (!isSupportedPlatform()) {
      return;
    }
    if (isMacOS()) {
      // The native macOS handler is a no-op (posthog-ios push is iOS-only).
      printIfDebug(
          'unregisterPushNotificationToken is not supported on macOS; nothing to unregister.');
      return;
    }

    try {
      await _methodChannel.invokeMethod('unregisterPushNotificationToken');
    } on PlatformException catch (exception) {
      printIfDebug('Exception on unregisterPushNotificationToken: $exception');
    }
  }

  @override
  Future<void> capturePushNotificationOpened({
    String? title,
    String? subtitle,
    String? body,
    Map<String, Object?>? payload,
    String? action,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('capturePushNotificationOpened', {
        if (title != null) 'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (body != null) 'body': body,
        if (payload != null) 'payload': PropertyNormalizer.normalize(payload),
        if (action != null) 'action': action,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exception on capturePushNotificationOpened: $exception');
    }
  }

  @override
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    if (!isSupportedPlatform() || isMacOS()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('startSessionRecording', resumeCurrent);
    } on PlatformException catch (exception) {
      printIfDebug('Exception on startSessionRecording: $exception');
    }
  }

  @override
  Future<void> stopSessionRecording() async {
    if (!isSupportedPlatform() || isMacOS()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('stopSessionRecording');
    } on PlatformException catch (exception) {
      printIfDebug('Exception on stopSessionRecording: $exception');
    }
  }

  @override
  Future<bool> isSessionReplayActive() async {
    if (!isSupportedPlatform() || isMacOS()) {
      return false;
    }

    try {
      final result = await _methodChannel.invokeMethod('isSessionReplayActive');
      return result as bool? ?? false;
    } on PlatformException catch (exception) {
      printIfDebug('Exception on isSessionReplayActive: $exception');
      return false;
    }
  }
}
