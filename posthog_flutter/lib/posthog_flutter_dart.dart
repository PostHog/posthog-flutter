import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:posthog_dart/posthog_dart.dart' as dart_sdk;

import 'src/error_tracking/dart_exception_processor.dart';
import 'src/feature_flag_result.dart';
import 'src/posthog_config.dart';
import 'src/posthog_event.dart';
import 'src/posthog_flutter_platform_interface.dart';
import 'src/util/logging.dart';
import 'src/utils/property_normalizer.dart';
import 'src/utils/capture_utils.dart';
import 'src/posthog_constants.dart';

/// Dart-based platform implementation for Linux and Windows.
///
/// Uses posthog_dart SDK directly instead of native method channels.
class PosthogFlutterDart extends PosthogFlutterPlatformInterface {
  dart_sdk.PostHog? _client;
  PostHogConfig? _config;
  List<BeforeSendCallback> _beforeSendCallbacks = [];
  OnFeatureFlagsCallback? _onFeatureFlagsCallback;
  void Function()? _featureFlagUnsubscribe;

  /// Registers this implementation as the platform instance.
  static void registerWith() {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterDart();
  }

  /// Applies the beforeSend callbacks to an event in order.
  Future<PostHogEvent?> _runBeforeSend(
    String eventName,
    Map<String, Object>? properties, {
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    var event = PostHogEvent(
      event: eventName,
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );

    if (_beforeSendCallbacks.isEmpty) return event;

    for (final callback in _beforeSendCallbacks) {
      try {
        final result = callback(event);
        final resolved =
            result is Future<PostHogEvent?> ? await result : result;
        if (resolved == null) return null;
        event = resolved;
      } catch (e) {
        printIfDebug('[PostHog] beforeSend callback threw exception: $e');
      }
    }
    return event;
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    _config = config;
    _onFeatureFlagsCallback = config.onFeatureFlags;
    _beforeSendCallbacks = config.beforeSend;

    try {
      // Use application support directory for persistent storage
      final storagePath = p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.',
        '.posthog',
      );

      _client = dart_sdk.PostHog(
        config.apiKey,
        options: config.toCoreConfig(),
        storage: dart_sdk.FileStorage(storagePath),
      );

      if (config.debug) {
        printIfDebug(
            '[PostHog] Dart SDK initialized for ${Platform.operatingSystem}');
      }

      // Listen for feature flag updates
      if (_onFeatureFlagsCallback != null) {
        _featureFlagUnsubscribe = _client!.onFeatureFlags((_) {
          _onFeatureFlagsCallback?.call();
        });
      }
    } catch (e) {
      printIfDebug('[PostHog] Exception on setup: $e');
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    final client = _client;
    if (client == null) return;

    try {
      final normalizedUserProperties = userProperties != null
          ? PropertyNormalizer.normalize(userProperties)
          : null;
      final normalizedUserPropertiesSetOnce = userPropertiesSetOnce != null
          ? PropertyNormalizer.normalize(userPropertiesSetOnce)
          : null;

      final props = <String, Object?>{};
      if (normalizedUserProperties != null) {
        props[r'$set'] = normalizedUserProperties;
      }
      if (normalizedUserPropertiesSetOnce != null) {
        props[r'$set_once'] = normalizedUserPropertiesSetOnce;
      }

      client.identify(userId, properties: props.isNotEmpty ? props : null);
    } catch (e) {
      printIfDebug('[PostHog] Exception on identify: $e');
    }
  }

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
  }) async {
    final client = _client;
    if (client == null) return;

    try {
      final normalizedSet = userPropertiesToSet != null
          ? PropertyNormalizer.normalize(userPropertiesToSet)
          : null;
      final normalizedSetOnce = userPropertiesToSetOnce != null
          ? PropertyNormalizer.normalize(userPropertiesToSetOnce)
          : null;

      client.setPersonProperties(
        userPropertiesToSet: normalizedSet?.cast<String, Object?>(),
        userPropertiesToSetOnce: normalizedSetOnce?.cast<String, Object?>(),
      );
    } catch (e) {
      printIfDebug('[PostHog] Exception on setPersonProperties: $e');
    }
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    final client = _client;
    if (client == null) return;

    final processedEvent = await _runBeforeSend(
      eventName,
      properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );

    if (processedEvent == null) {
      printIfDebug('[PostHog] Event dropped by beforeSend: $eventName');
      return;
    }

    try {
      final extracted = CaptureUtils.extractUserProperties(
        properties: processedEvent.properties,
        userProperties: processedEvent.userProperties,
        userPropertiesSetOnce: processedEvent.userPropertiesSetOnce,
      );

      final normalizedProperties = extracted.properties != null
          ? PropertyNormalizer.normalize(extracted.properties!)
          : null;
      final normalizedUserProperties = extracted.userProperties != null
          ? PropertyNormalizer.normalize(extracted.userProperties!)
          : null;
      final normalizedUserPropertiesSetOnce =
          extracted.userPropertiesSetOnce != null
              ? PropertyNormalizer.normalize(extracted.userPropertiesSetOnce!)
              : null;

      final allProps = <String, Object?>{
        ...?normalizedProperties?.cast<String, Object?>(),
        if (normalizedUserProperties != null) r'$set': normalizedUserProperties,
        if (normalizedUserPropertiesSetOnce != null)
          r'$set_once': normalizedUserPropertiesSetOnce,
      };

      client.capture(
        processedEvent.event,
        properties: allProps.isNotEmpty ? allProps : null,
      );
    } catch (e) {
      printIfDebug('[PostHog] Exception on capture: $e');
    }
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    final client = _client;
    if (client == null) return;

    final propsWithScreenName = <String, Object>{
      PostHogPropertyName.screenName: screenName,
      ...?properties,
    };

    final processedEvent =
        await _runBeforeSend(PostHogEventName.screen, propsWithScreenName);
    if (processedEvent == null) {
      printIfDebug('[PostHog] Screen event dropped by beforeSend: $screenName');
      return;
    }

    if (processedEvent.event != PostHogEventName.screen) {
      await capture(
        eventName: processedEvent.event,
        properties: processedEvent.properties?.cast<String, Object>(),
      );
      return;
    }

    try {
      final normalizedProperties = processedEvent.properties?.isNotEmpty == true
          ? PropertyNormalizer.normalize(
              processedEvent.properties!.cast<String, Object>())
          : null;

      client.capture(
        r'$screen',
        properties: <String, Object?>{
          r'$screen_name': screenName,
          ...?normalizedProperties?.cast<String, Object?>(),
        },
      );
    } catch (e) {
      printIfDebug('[PostHog] Exception on screen: $e');
    }
  }

  @override
  Future<void> alias({required String alias}) async {
    final client = _client;
    if (client == null) return;

    try {
      client.alias(alias);
    } catch (e) {
      printIfDebug('[PostHog] Exception on alias: $e');
    }
  }

  @override
  Future<String> getDistinctId() async {
    final client = _client;
    if (client == null) return '';

    try {
      return client.getDistinctId();
    } catch (e) {
      printIfDebug('[PostHog] Exception on getDistinctId: $e');
      return '';
    }
  }

  @override
  Future<void> reset() async {
    final client = _client;
    if (client == null) return;

    try {
      client.reset();
    } catch (e) {
      printIfDebug('[PostHog] Exception on reset: $e');
    }
  }

  @override
  Future<void> disable() async {
    final client = _client;
    if (client == null) return;

    try {
      client.optOut();
    } catch (e) {
      printIfDebug('[PostHog] Exception on disable: $e');
    }
  }

  @override
  Future<void> enable() async {
    final client = _client;
    if (client == null) return;

    try {
      client.optIn();
    } catch (e) {
      printIfDebug('[PostHog] Exception on enable: $e');
    }
  }

  @override
  Future<bool> isOptOut() async {
    // posthog_dart doesn't expose isOptOut directly; use internal state
    // For now, return false as default
    return false;
  }

  @override
  Future<void> debug(bool enabled) async {
    // posthog_dart logging is configured at construction; no runtime toggle
    printIfDebug('[PostHog] Debug mode: $enabled');
  }

  @override
  Future<bool> isFeatureEnabled(String key) async {
    final client = _client;
    if (client == null) return false;

    try {
      return client.isFeatureEnabled(key) ?? false;
    } catch (e) {
      printIfDebug('[PostHog] Exception on isFeatureEnabled: $e');
      return false;
    }
  }

  @override
  Future<void> reloadFeatureFlags() async {
    final client = _client;
    if (client == null) return;

    try {
      await client.reloadFeatureFlagsAsync();
    } catch (e) {
      printIfDebug('[PostHog] Exception on reloadFeatureFlags: $e');
    }
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {
    final client = _client;
    if (client == null) return;

    try {
      final normalizedGroupProperties = groupProperties != null
          ? PropertyNormalizer.normalize(groupProperties)
          : null;

      client.group(
        groupType,
        groupKey,
        groupProperties: normalizedGroupProperties?.cast<String, Object?>(),
      );
    } catch (e) {
      printIfDebug('[PostHog] Exception on group: $e');
    }
  }

  @override
  Future<Object?> getFeatureFlag({required String key}) async {
    final client = _client;
    if (client == null) return null;

    try {
      return client.getFeatureFlag(key);
    } catch (e) {
      printIfDebug('[PostHog] Exception on getFeatureFlag: $e');
      return null;
    }
  }

  @override
  Future<Object?> getFeatureFlagPayload({required String key}) async {
    final client = _client;
    if (client == null) return null;

    try {
      final result = client.getFeatureFlagResult(key,
          options:
              const dart_sdk.PostHogFeatureFlagResultOptions(sendEvent: false));
      return result?.payload;
    } catch (e) {
      printIfDebug('[PostHog] Exception on getFeatureFlagPayload: $e');
      return null;
    }
  }

  @override
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool sendEvent = true,
  }) async {
    final client = _client;
    if (client == null) return null;

    try {
      return client.getFeatureFlagResult(key,
          options:
              dart_sdk.PostHogFeatureFlagResultOptions(sendEvent: sendEvent));
    } catch (e) {
      printIfDebug('[PostHog] Exception on getFeatureFlagResult: $e');
      return null;
    }
  }

  @override
  Future<void> register(String key, Object value) async {
    final client = _client;
    if (client == null) return;

    try {
      client.register({key: value});
    } catch (e) {
      printIfDebug('[PostHog] Exception on register: $e');
    }
  }

  @override
  Future<void> unregister(String key) async {
    final client = _client;
    if (client == null) return;

    try {
      client.unregister(key);
    } catch (e) {
      printIfDebug('[PostHog] Exception on unregister: $e');
    }
  }

  @override
  Future<void> flush() async {
    final client = _client;
    if (client == null) return;

    try {
      await client.flush();
    } catch (e) {
      printIfDebug('[PostHog] Exception on flush: $e');
    }
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {
    final client = _client;
    if (client == null) return;

    try {
      final exceptionProps = DartExceptionProcessor.processException(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
        inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
        inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
        inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
      );

      final processedEvent = await _runBeforeSend(
          PostHogEventName.exception, exceptionProps.cast<String, Object>());
      if (processedEvent == null) {
        printIfDebug(
            '[PostHog] Exception event dropped by beforeSend: ${error.runtimeType}');
        return;
      }

      if (processedEvent.event != PostHogEventName.exception) {
        await capture(
          eventName: processedEvent.event,
          properties: processedEvent.properties?.cast<String, Object>(),
        );
        return;
      }

      final normalizedData = processedEvent.properties != null
          ? PropertyNormalizer.normalize(
              processedEvent.properties!.cast<String, Object>())
          : <String, Object>{};

      client.capture(
        r'$exception',
        properties: normalizedData.cast<String, Object?>(),
      );
    } catch (e) {
      printIfDebug('[PostHog] Exception in captureException: $e');
    }
  }

  @override
  Future<void> close() async {
    final client = _client;
    if (client == null) return;

    try {
      _featureFlagUnsubscribe?.call();
      _featureFlagUnsubscribe = null;
      await client.shutdown();
      _client = null;
    } catch (e) {
      printIfDebug('[PostHog] Exception on close: $e');
    }
  }

  @override
  Future<String?> getSessionId() async {
    final client = _client;
    if (client == null) return null;

    try {
      return client.getSessionId();
    } catch (e) {
      printIfDebug('[PostHog] Exception on getSessionId: $e');
      return null;
    }
  }

  @override
  Future<void> openUrl(String url) async {
    // Not directly supported on Linux/Windows via posthog_dart
    printIfDebug(
        '[PostHog] openUrl is not supported on ${Platform.operatingSystem}');
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    // Surveys are not yet supported on Linux/Windows
    printIfDebug(
        '[PostHog] Surveys are not supported on ${Platform.operatingSystem}');
  }

  @override
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    // Session recording is not supported on Linux/Windows
  }

  @override
  Future<void> stopSessionRecording() async {
    // Session recording is not supported on Linux/Windows
  }

  @override
  Future<bool> isSessionReplayActive() async {
    return false;
  }
}
