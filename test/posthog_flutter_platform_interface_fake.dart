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

/// Captured event call data
class CapturedEventCall {
  final String eventName;
  final Map<String, Object>? properties;
  final Map<String, Object>? groups;

  CapturedEventCall({
    required this.eventName,
    this.properties,
    this.groups,
  });
}

class PosthogFlutterPlatformFake extends PosthogFlutterPlatformInterface {
  String? screenName;
  OnFeatureFlagsCallback? registeredOnFeatureFlagsCallback;
  final List<CapturedExceptionCall> capturedExceptions = [];
  final List<CapturedEventCall> capturedEvents = [];
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

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? groups,
  }) async {
    capturedEvents.add(CapturedEventCall(
      eventName: eventName,
      properties: properties,
      groups: groups,
    ));
  }
}
