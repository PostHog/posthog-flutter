import '../feature_flag_result.dart';
import '../posthog_config.dart';
import '../util/logging.dart';

extension PostHogConfigSerialization on PostHogConfig {
  Map<String, dynamic> toMap() {
    return {
      'projectToken': projectToken,
      'host': host,
      'flushAt': flushAt,
      'maxQueueSize': maxQueueSize,
      'maxBatchSize': maxBatchSize,
      'flushInterval': flushInterval.inSeconds,
      'sendFeatureFlagEvents': sendFeatureFlagEvent,
      'preloadFeatureFlags': preloadFeatureFlags,
      'captureApplicationLifecycleEvents': captureApplicationLifecycleEvents,
      'rageClickConfig': rageClickConfig.toMap(),
      'debug': debug,
      'optOut': optOut,
      'surveys': surveys,
      'personProfiles': personProfiles.name,
      'compression': compression.name,
      'sessionReplay': sessionReplay,
      'dataMode': dataMode.name,
      'sessionReplayConfig': sessionReplayConfig.toMap(),
      'errorTrackingConfig': errorTrackingConfig.toMap(),
      'logs': logsConfig.toMap(),
      'capturePushNotificationSubscriptions':
          capturePushNotificationSubscriptions,
      'capturePushNotificationOpened': capturePushNotificationOpened,
      // A closure can't cross the channel. This tells native whether to install
      // a bridging provider at all — installing one the host didn't ask for
      // would change how the native SDK handles a 401 on the subscription call.
      'pushIdentityProviderEnabled': pushIdentityProvider != null,
      if (bootstrap != null) 'bootstrap': bootstrap!.toMap(),
    };
  }
}

extension PostHogBootstrapConfigSerialization on PostHogBootstrapConfig {
  /// Only the dimensions that were set are included; [isIdentifiedId] is always
  /// sent so the native SDK doesn't have to infer it.
  Map<String, Object?> toMap() {
    final flags = featureFlags;
    if (flags != null) {
      for (final entry in flags.entries) {
        // Only bool/String are served (see [featureFlags]); the native SDKs drop
        // anything else silently, so warn instead of leaving no trace.
        if (entry.value is! bool && entry.value is! String) {
          printIfDebug(
            '[PostHog] bootstrap featureFlags["${entry.key}"] is '
            '${entry.value.runtimeType}; only bool and String values are served, '
            'so this entry will be ignored.',
          );
        }
      }
    }
    return {
      if (distinctId != null) 'distinctId': distinctId,
      'isIdentifiedId': isIdentifiedId,
      if (featureFlags != null) 'featureFlags': featureFlags,
      if (featureFlagPayloads != null)
        'featureFlagPayloads': featureFlagPayloads,
    };
  }
}

extension PostHogLogsConfigSerialization on PostHogLogsConfig {
  /// Only fields the user set are included, so unset fields keep the native
  /// default. [beforeSend] is intentionally omitted: it runs in Dart and never
  /// crosses the platform channel.
  Map<String, dynamic> toMap() {
    return {
      if (serviceName != null) 'serviceName': serviceName,
      if (serviceVersion != null) 'serviceVersion': serviceVersion,
      if (environment != null) 'environment': environment,
      if (resourceAttributes.isNotEmpty)
        'resourceAttributes': resourceAttributes,
      if (flushInterval != null)
        'flushIntervalSeconds': _wholeSeconds(flushInterval!),
      if (flushAt != null) 'flushAt': flushAt,
      if (maxBatchSize != null) 'maxBatchSize': maxBatchSize,
      if (maxBufferSize != null) 'maxBufferSize': maxBufferSize,
      if (rateCapMaxLogs != null) 'rateCapMaxLogs': rateCapMaxLogs,
      if (rateCapWindow != null)
        'rateCapWindowSeconds': _wholeSeconds(rateCapWindow!),
    };
  }

  /// The native flush interval and rate-cap window are whole seconds. A
  /// sub-second [Duration] truncates to `0`, which the native SDK treats as
  /// "disabled" (rate cap) or continuous flushing — surprising for a caller who
  /// set, say, 500ms. Floor at 1s, the smallest value the native API can honor.
  static int _wholeSeconds(Duration duration) =>
      duration.inSeconds < 1 ? 1 : duration.inSeconds;
}

extension PostHogRageClickConfigSerialization on PostHogRageClickConfig {
  Map<String, Object> toMap() {
    return {
      'enabled': enabled,
      'thresholdPoints': thresholdPoints,
      'timeoutInterval':
          timeoutInterval.inMicroseconds / Duration.microsecondsPerSecond,
      'minimumTapCount': minimumTapCount,
    };
  }
}

extension PostHogSessionReplayConfigSerialization
    on PostHogSessionReplayConfig {
  Map<String, dynamic> toMap() {
    return {
      'captureTouches': captureTouches,
      'maskAllImages': maskAllImages,
      'maskAllTexts': maskAllTexts,
      'throttleDelayMs': throttleDelay.inMilliseconds,
      'maskAllPlatformViews': maskAllPlatformViews,
      'captureNativeScreens': captureNativeScreens,
      'verifyScreenshotMaskAlignment': verifyScreenshotMaskAlignment,
      'screenshotScale': screenshotScale,
      'screenshotCompressionQuality': screenshotCompressionQuality,
      'screenshotColorMode': screenshotColorMode.name,
      if (sampleRate != null) 'sampleRate': sampleRate,
    };
  }
}

extension PostHogErrorTrackingConfigSerialization
    on PostHogErrorTrackingConfig {
  Map<String, dynamic> toMap() {
    return {
      'inAppIncludes': inAppIncludes,
      'inAppExcludes': inAppExcludes,
      'inAppByDefault': inAppByDefault,
      'captureFlutterErrors': captureFlutterErrors,
      'captureSilentFlutterErrors': captureSilentFlutterErrors,
      'capturePlatformDispatcherErrors': capturePlatformDispatcherErrors,
      'captureNativeExceptions': captureNativeExceptions,
      'captureNativeCrashes': captureNativeCrashes,
      'captureIsolateErrors': captureIsolateErrors,
      'exceptionSteps': exceptionSteps.toMap(),
    };
  }
}

extension PostHogExceptionStepsConfigSerialization
    on PostHogExceptionStepsConfig {
  Map<String, Object> toMap() {
    return {
      'enabled': enabled,
      'maxBytes': maxBytes,
    };
  }
}

/// Returns `null` if [result] is not a [Map]. Falls back to [fallbackKey] when
/// the map has no `key`.
PostHogFeatureFlagResult? featureFlagResultFromMap(
  Object? result,
  String fallbackKey,
) {
  if (result is! Map) return null;

  return PostHogFeatureFlagResult(
    key: result['key'] as String? ?? fallbackKey,
    enabled: result['enabled'] as bool? ?? false,
    variant: result['variant'] as String?,
    payload: result['payload'],
  );
}
