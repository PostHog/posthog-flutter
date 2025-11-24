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
  final List<CapturedExceptionCall> capturedExceptions = [];

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    this.screenName = screenName;
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
