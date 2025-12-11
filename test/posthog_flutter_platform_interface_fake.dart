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
}
