// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';
import 'package:posthog_flutter/src/util/logging.dart';
import 'package:posthog_flutter/src/utils/channel_serialization.dart';
import 'package:posthog_flutter/src/utils/property_normalizer.dart';

import 'src/feature_flag_result.dart';
import 'src/feature_flags_loaded.dart';
import 'src/logs/posthog_log_severity.dart';
import 'src/posthog_config.dart';
import 'src/posthog_constants.dart';
import 'src/posthog_event.dart';
import 'src/posthog_flutter_platform_interface.dart';
import 'src/posthog_flutter_web_handler.dart';
import 'src/utils/before_send.dart';
import 'src/utils/call_order.dart';
import 'src/replay/web/web_canvas_mask_provider.dart';
import 'src/utils/capture_utils.dart';
import 'src/utils/event_options.dart';
import 'src/utils/feature_event.dart';

/// A web implementation of the PosthogFlutterPlatform of the PosthogFlutter plugin.
class PosthogFlutterWeb extends PosthogFlutterPlatformInterface {
  /// Constructs a PosthogFlutterWeb
  PosthogFlutterWeb();

  /// Stored configuration for accessing inAppIncludes and other settings
  PostHogConfig? _config;

  /// Copied at setup. Event beforeSend runs here, before posthog-js, the same
  /// way [PosthogFlutterIO] runs it before the platform channel.
  List<BeforeSendCallback> _beforeSendCallbacks = [];

  // posthog-js has no current screen, so the feature events get it from here
  // the way native SDKs stamp it: the last screen beforeSend accepted, under
  // its final name, until close().
  String? _currentScreen;

  final _order = CallOrder();

  /// Without callbacks the event comes back synchronously, so it is handed
  /// over in the same call and nothing has to wait for it.
  FutureOr<PostHogEvent?> _runBeforeSend(
    String eventName,
    Map<String, Object>? properties, {
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) {
    final event = PostHogEvent(
      event: eventName,
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
      options: options == null ? null : {...options},
    );
    return _beforeSendCallbacks.isEmpty
        ? event
        : applyBeforeSend(_beforeSendCallbacks, event);
  }

  /// posthog-js sends these calls' events without event properties, so
  /// options can't be attached.
  static void _logUnsupportedOptions(
    String method,
    Map<String, Object?>? options,
  ) {
    if (cleanEventOptions(options) == null) return;
    printIfDebug('[PostHog] $method options are not supported on web and '
        'were dropped.');
  }

  Future<dynamic> _call(MethodCall call) =>
      _order.run(() => handleWebMethodCall(call));

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'posthog_flutter',
      const StandardMethodCodec(),
      registrar,
    );
    final instance = PosthogFlutterWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);

    // Set the platform instance so that Posthog() can call methods directly
    // on the web implementation instead of going through the method channel.
    // This is required because method channels can only pass serializable data,
    // not function callbacks like onFeatureFlags.
    PosthogFlutterPlatformInterface.instance = instance;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    // The 'setup' call is now handled by the setup method override.
    // Other method calls are delegated to handleWebMethodCall.
    if (call.method == 'setup') {
      // This case should ideally not be hit if Posthog().setup directly calls the overridden setup.
      // However, to be safe, we can log or ignore.
      // For now, let's assume direct call to overridden setup handles it.
      return null;
    }
    return _call(call);
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    // It's assumed posthog-js is initialized by the user in their HTML.
    // This setup primarily hooks into the existing posthog-js instance.

    // If projectToken and host are in config, and posthog.init is to be handled by plugin:
    // This is an example if we wanted the plugin to also call posthog.init()
    // final jsOptions = <String, dynamic>{
    //   'api_host': config.host,
    //   // Add other relevant options from PostHogConfig if needed for JS init
    // }.jsify();
    // posthog?.callMethod('init'.toJS, config.projectToken.toJS, jsOptions);

    final ph = posthog;
    _config = config;
    _beforeSendCallbacks = config.beforeSend;

    // posthog-js is initialized by the host app, so a few config options never
    // reach it. Warn instead of silently ignoring them.
    if (!config.preloadFeatureFlags) {
      printIfDebug(
        'Warning: PostHogConfig.preloadFeatureFlags is not applied on Flutter web. '
        'posthog-js is initialized by your app, so set '
        'advanced_disable_feature_flags_on_first_load in your posthog.init({...}) call instead.',
      );
    }
    if (config.evaluationContexts?.isNotEmpty ?? false) {
      printIfDebug(
        'Warning: PostHogConfig.evaluationContexts is not applied on Flutter web. '
        'Set evaluation_contexts in your posthog.init({...}) call instead.',
      );
    }
    if (config.bootstrap != null) {
      printIfDebug(
        'Warning: PostHogConfig.bootstrap is not applied on Flutter web. '
        'Configure bootstrap in your posthog.init({...}) call instead.',
      );
    }

    WebCanvasMaskProvider(config).register();

    if (config.onFeatureFlags != null && ph != null) {
      final dartCallback = config.onFeatureFlags!;

      // JS SDK calls with: (flags: string[], variants: Record, context?: {errorsLoading})
      final jsCallback =
          (JSArray jsFlags, JSObject jsFlagVariants, [JSObject? jsContext]) {
        dartCallback(featureFlagsLoadedFromMap({
          'variants': jsFlagVariants.dartify(),
          'errorsLoading': (jsContext?.dartify() as Map?)?['errorsLoading'],
        }));
      }.toJS;

      ph.onFeatureFlags(jsCallback);
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('identify', options);
    return _call(
      MethodCall('identify', {
        'userId': userId,
        if (userProperties != null) 'userProperties': userProperties,
        if (userPropertiesSetOnce != null)
          'userPropertiesSetOnce': userPropertiesSetOnce,
      }),
    );
  }

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('setPersonProperties', options);
    if ((userPropertiesToSet?.isEmpty ?? true) &&
        (userPropertiesToSetOnce?.isEmpty ?? true)) {
      return;
    }

    return _call(
      MethodCall('setPersonProperties', {
        if (userPropertiesToSet != null)
          'userPropertiesToSet': userPropertiesToSet,
        if (userPropertiesToSetOnce != null)
          'userPropertiesToSetOnce': userPropertiesToSetOnce,
      }),
    );
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) =>
      _order.event(
        () => _runBeforeSend(
          eventName,
          properties,
          userProperties: userProperties,
          userPropertiesSetOnce: userPropertiesSetOnce,
          options: options,
        ),
        (processedEvent) => _sendCapture(eventName, processedEvent),
      );

  Future<void> _sendCapture(
    String eventName,
    PostHogEvent? processedEvent,
  ) async {
    if (processedEvent == null) {
      printIfDebug('[PostHog] Event dropped by beforeSend: $eventName');
      return;
    }

    final extracted = CaptureUtils.extractUserProperties(
      properties: processedEvent.properties,
      userProperties: processedEvent.userProperties,
      userPropertiesSetOnce: processedEvent.userPropertiesSetOnce,
    );

    final extractedProperties = _withOptionProperties(
      extracted.properties,
      processedEvent.options,
      processedEvent.event,
    );
    final extractedUserProperties = extracted.userProperties;
    final extractedUserPropertiesSetOnce = extracted.userPropertiesSetOnce;

    final normalizedProperties = extractedProperties != null
        ? PropertyNormalizer.normalize(extractedProperties)
        : null;
    final normalizedUserProperties = extractedUserProperties != null
        ? PropertyNormalizer.normalize(extractedUserProperties)
        : null;
    final normalizedUserPropertiesSetOnce =
        extractedUserPropertiesSetOnce != null
            ? PropertyNormalizer.normalize(extractedUserPropertiesSetOnce)
            : null;

    return _call(
      MethodCall('capture', {
        'eventName': processedEvent.event,
        if (normalizedProperties != null) 'properties': normalizedProperties,
        if (normalizedUserProperties != null)
          'userProperties': normalizedUserProperties,
        if (normalizedUserPropertiesSetOnce != null)
          'userPropertiesSetOnce': normalizedUserPropertiesSetOnce,
      }),
    );
  }

  /// posthog-js has no AI capture, so AI events are not sent on web.
  @override
  Future<String?> captureAi({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    printIfDebug('[PostHog] captureAi is not supported on web. '
        'The event "$eventName" was not sent.');
    return null;
  }

  /// posthog-js has no options for these keys, so they are sent as their
  /// legacy properties, winning over a legacy property set on the event.
  static Map<String, Object>? _withOptionProperties(
    Map<String, Object>? properties,
    Map<String, Object?>? options,
    String eventName,
  ) {
    final optionProperties =
        eventOptionsToLegacyProperties(options, method: eventName);
    if (optionProperties.isEmpty) return properties;
    return {...?properties, ...optionProperties};
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
    final normalizedAttributes =
        attributes != null ? PropertyNormalizer.normalize(attributes) : null;

    return _call(
      MethodCall('captureLog', {
        'body': body,
        'level': level.name,
        if (normalizedAttributes != null) 'attributes': normalizedAttributes,
        if (traceId != null) 'traceId': traceId,
        if (spanId != null) 'spanId': spanId,
        // traceFlags 0 is meaningful (W3C sampled-false); only omit when null.
        if (traceFlags != null) 'traceFlags': traceFlags,
      }),
    );
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
    Map<String, Object?>? options,
  }) async {
    // The screen name argument wins over a properties `$screen_name`.
    // beforeSend still runs after this and can change the name.
    final propsWithScreenName = <String, Object>{
      ...?properties,
      PostHogPropertyName.screenName: screenName,
    };

    return _order.event(
      () => _runBeforeSend(
        PostHogEventName.screen,
        propsWithScreenName,
        options: options,
      ),
      (processedEvent) => _sendScreen(screenName, processedEvent),
    );
  }

  Future<void> _sendScreen(
    String screenName,
    PostHogEvent? processedEvent,
  ) async {
    if (processedEvent == null) {
      printIfDebug('[PostHog] Screen event dropped by beforeSend: $screenName');
      return;
    }

    if (processedEvent.event != PostHogEventName.screen) {
      await capture(
        eventName: processedEvent.event,
        properties: processedEvent.properties?.cast<String, Object>(),
        options: processedEvent.options,
      );
      return;
    }

    final finalScreenName =
        processedEvent.properties?[PostHogPropertyName.screenName] as String? ??
            screenName;
    _currentScreen = finalScreenName;
    processedEvent.properties?.remove(PostHogPropertyName.screenName);
    final remaining = _withOptionProperties(
      processedEvent.properties,
      processedEvent.options,
      PostHogEventName.screen,
    );

    return _call(
      MethodCall('screen', {
        'screenName': finalScreenName,
        if (remaining != null && remaining.isNotEmpty) 'properties': remaining,
      }),
    );
  }

  @override
  Future<void> alias({
    required String alias,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('alias', options);
    return _call(MethodCall('alias', {'alias': alias}));
  }

  @override
  Future<String> getDistinctId() async {
    final result = await _call(const MethodCall('distinctId'));
    return result as String? ?? '';
  }

  @override
  Future<void> captureFeatureView({
    required String flag,
    String? flagVariant,
  }) =>
      _captureFeatureEvent(r'$feature_view', flag, flagVariant);

  @override
  Future<void> captureFeatureInteraction({
    required String flag,
    String? flagVariant,
  }) =>
      _captureFeatureEvent(r'$feature_interaction', flag, flagVariant);

  Future<void> _captureFeatureEvent(
    String event,
    String flag,
    String? flagVariant,
  ) =>
      // The flag lookup belongs to the send step so it reads the flags of the
      // user at hand-over time; an async hook keeps later calls waiting for it.
      _order.event<void>(
        () => Future<void>.value(),
        (_) async {
          final result = flagVariant == null
              ? await getFeatureFlagResult(
                  key: flag, sendFeatureFlagEvent: false)
              : null;
          final captured = featureEvent(
              event, flag, flagVariant ?? result?.variant ?? result?.enabled);
          if (captured == null) return;
          final screenName = _currentScreen;
          await capture(
            eventName: event,
            properties: {
              ...captured.properties,
              if (screenName != null)
                PostHogPropertyName.screenName: screenName,
            },
            userProperties: captured.userProperties,
          );
        },
      );

  @override
  Future<void> reset() async {
    return _call(const MethodCall('reset'));
  }

  @override
  Future<void> optOut() async {
    return _call(const MethodCall('disable'));
  }

  @override
  Future<void> optIn() async {
    return _call(const MethodCall('enable'));
  }

  @override
  Future<bool> isOptOut() async {
    final result = await _call(const MethodCall('isOptOut'));
    return result as bool? ?? true;
  }

  @override
  Future<void> debug(bool enabled) async {
    return _call(MethodCall('debug', {'debug': enabled}));
  }

  @override
  Future<void> register(String key, Object value) async {
    return _call(
      MethodCall('register', {'key': key, 'value': value}),
    );
  }

  @override
  Future<void> unregister(String key) async {
    return _call(MethodCall('unregister', {'key': key}));
  }

  @override
  Future<bool> isFeatureEnabled(String key,
      {bool? sendFeatureFlagEvent}) async {
    final result = await _call(
      MethodCall('isFeatureEnabled', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      }),
    );
    return result as bool? ?? false;
  }

  @override
  Future<PostHogFeatureFlagsLoaded> reloadFeatureFlags() async {
    return featureFlagsLoadedFromMap(
        await _call(const MethodCall('reloadFeatureFlags')));
  }

  @override
  Future<void> setPersonPropertiesForFlags(
    Map<String, Object> userProperties,
  ) async {
    return _call(
      MethodCall('setPersonPropertiesForFlags', {
        'userProperties': userProperties,
      }),
    );
  }

  @override
  Future<void> resetPersonPropertiesForFlags() async {
    return _call(
      const MethodCall('resetPersonPropertiesForFlags'),
    );
  }

  @override
  Future<void> setGroupPropertiesForFlags(
    String groupType,
    Map<String, Object> groupProperties,
  ) async {
    return _call(
      MethodCall('setGroupPropertiesForFlags', {
        'groupType': groupType,
        'groupProperties': groupProperties,
      }),
    );
  }

  @override
  Future<void> resetGroupPropertiesForFlags({String? groupType}) async {
    return _call(
      MethodCall('resetGroupPropertiesForFlags', {
        if (groupType != null) 'groupType': groupType,
      }),
    );
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('group', options);
    return _call(
      MethodCall('group', {
        'groupType': groupType,
        'groupKey': groupKey,
        if (groupProperties != null) 'groupProperties': groupProperties,
      }),
    );
  }

  @override
  Future<Object?> getFeatureFlag({
    required String key,
    bool? sendFeatureFlagEvent,
  }) async {
    return _call(MethodCall('getFeatureFlag', {
      'key': key,
      if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
    }));
  }

  @override
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool? sendFeatureFlagEvent,
  }) async {
    final result = await _call(
      MethodCall('getFeatureFlagResult', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      }),
    );

    // Web SDK returns: { key, enabled, variant, payload }
    return featureFlagResultFromMap(result, key);
  }

  @override
  Future<List<PostHogFeatureFlagResult>?> getAllFeatureFlags() async {
    final results = await _call(const MethodCall('getAllFeatureFlags'));
    if (results is! List) return null;
    return results
        .map((result) => featureFlagResultFromMap(result, ''))
        .nonNulls
        .toList();
  }

  @override
  Future<void> flush() async {
    return _call(const MethodCall('flush'));
  }

  @override
  Future<void> close() async {
    _currentScreen = null;
    return _call(const MethodCall('close'));
  }

  @override
  Future<String?> getSessionId() async {
    final result = await _call(const MethodCall('getSessionId'));
    return result as String?;
  }

  @override
  Future<void> openUrl(String url) async {
    // Not supported on web
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    // Not supported on web - surveys handled by posthog-js
  }

  @override
  Future<void> registerPushNotificationToken(
    String deviceToken, {
    String? appId,
  }) async {
    // Not supported on web - posthog-js has no push subscription API
  }

  @override
  Future<void> unregisterPushNotificationToken() async {
    // Not supported on web - posthog-js has no push subscription API
  }

  @override
  Future<void> capturePushNotificationOpened({
    String? title,
    String? subtitle,
    String? body,
    Map<String, Object?>? payload,
    String? action,
  }) async {
    // Not supported on web - posthog-js has no push subscription API
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
    Map<String, Object?>? options,
  }) async {
    try {
      final exceptionData = DartExceptionProcessor.processException(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
        inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
        inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
        inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
      );

      return await _order.event(
        () => _runBeforeSend(
          PostHogEventName.exception,
          exceptionData.cast<String, Object>(),
          options: options,
        ),
        (processedEvent) => _sendException(error, processedEvent),
      );
    } catch (error) {
      printIfDebug('Exception in captureException: $error');
    }
  }

  Future<void> _sendException(
    Object error,
    PostHogEvent? processedEvent,
  ) async {
    if (processedEvent == null) {
      printIfDebug(
        '[PostHog] Exception event dropped by beforeSend: ${error.runtimeType}',
      );
      return;
    }

    if (processedEvent.event != PostHogEventName.exception) {
      await capture(
        eventName: processedEvent.event,
        properties: processedEvent.properties?.cast<String, Object>(),
        options: processedEvent.options,
      );
      return;
    }

    final normalizedData = PropertyNormalizer.normalize(
      _withOptionProperties(
            processedEvent.properties?.cast<String, Object>(),
            processedEvent.options,
            PostHogEventName.exception,
          ) ??
          <String, Object>{},
    );

    return _call(
      MethodCall('captureException', {'properties': normalizedData}),
    );
  }

  @override
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    return _call(
      MethodCall('startSessionRecording', {'resumeCurrent': resumeCurrent}),
    );
  }

  @override
  Future<void> stopSessionRecording() async {
    return _call(const MethodCall('stopSessionRecording'));
  }

  @override
  Future<bool> isSessionReplayActive() async {
    final result = await _call(
      const MethodCall('isSessionReplayActive'),
    );
    return result as bool? ?? false;
  }

  @override
  Future<void> addExceptionStep(
    String message, {
    Map<String, Object>? properties,
  }) async {
    final normalizedProperties =
        properties != null ? PropertyNormalizer.normalize(properties) : null;

    return _call(
      MethodCall('addExceptionStep', {
        'message': message,
        if (normalizedProperties != null) 'properties': normalizedProperties,
      }),
    );
  }
}
