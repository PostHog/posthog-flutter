import 'package:posthog_flutter/src/feature_flag_result.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

/// Captured exception call data
class CapturedExceptionCall {
  final Object error;
  final StackTrace? stackTrace;
  final Map<String, Object>? properties;

  CapturedExceptionCall({
    required this.error,
    this.stackTrace,
    this.properties,
  });
}

class PosthogFlutterPlatformFake extends PosthogFlutterPlatformInterface {
  String? screenName;
  OnFeatureFlagsCallback? registeredOnFeatureFlagsCallback;
  final List<CapturedExceptionCall> capturedExceptions = [];
  PostHogConfig? receivedConfig;

  // Feature flag test data
  final Map<String, Object?> featureFlagValues = {};
  final Map<String, Object?> featureFlagPayloads = {};

  // Call tracking for getFeatureFlagResult
  final List<Map<String, dynamic>> getFeatureFlagResultCalls = [];

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    this.screenName = screenName;
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    receivedConfig = config;
    registeredOnFeatureFlagsCallback = config.onFeatureFlags;
    // Simulate async operation if needed, but for fake, direct assignment is often enough.
    return Future.value();
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {
    capturedExceptions.add(CapturedExceptionCall(
      error: error,
      stackTrace: stackTrace,
      properties: properties,
    ));
  }

  @override
  Future<Object?> getFeatureFlag({required String key}) async {
    return featureFlagValues[key];
  }

  @override
  Future<Object?> getFeatureFlagPayload({required String key}) async {
    return featureFlagPayloads[key];
  }

  @override
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool sendEvent = true,
  }) async {
    getFeatureFlagResultCalls.add({'key': key, 'sendEvent': sendEvent});

    if (!featureFlagValues.containsKey(key)) {
      return null;
    }
    final value = featureFlagValues[key];
    final payload = featureFlagPayloads[key];
    return PostHogFeatureFlagResult.fromValueAndPayload(key, value, payload);
  }
}
