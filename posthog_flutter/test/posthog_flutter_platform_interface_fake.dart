import 'package:posthog_flutter/src/feature_flag_result.dart';
import 'package:posthog_flutter/src/logs/posthog_log_severity.dart';
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

/// Captured log call data
class CapturedLogCall {
  final String body;
  final PostHogLogSeverity level;
  final Map<String, Object>? attributes;
  final String? traceId;
  final String? spanId;
  final int? traceFlags;

  CapturedLogCall({
    required this.body,
    required this.level,
    this.attributes,
    this.traceId,
    this.spanId,
    this.traceFlags,
  });
}

class PosthogFlutterPlatformFake extends PosthogFlutterPlatformInterface {
  String? screenName;
  OnFeatureFlagsCallback? registeredOnFeatureFlagsCallback;
  final List<CapturedExceptionCall> capturedExceptions = [];
  PostHogConfig? receivedConfig;

  final List<bool> captureNativeScreensChanges = [];

  @override
  Future<void> setCaptureNativeScreens(bool enabled) async {
    captureNativeScreensChanges.add(enabled);
  }

  // Tracking for setPersonProperties calls
  final List<Map<String, dynamic>> setPersonPropertiesCalls = [];

  // Feature flag test data
  final Map<String, Object?> featureFlagValues = {};
  final Map<String, Object?> featureFlagPayloads = {};

  // Call tracking for getFeatureFlagResult
  final List<Map<String, dynamic>> getFeatureFlagResultCalls = [];

  // Call tracking for properties-for-flags + reload
  int reloadFeatureFlagsCount = 0;
  final List<Map<String, Object>> setPersonPropertiesForFlagsCalls = [];
  int resetPersonPropertiesForFlagsCount = 0;
  final List<Map<String, dynamic>> setGroupPropertiesForFlagsCalls = [];
  final List<String?> resetGroupPropertiesForFlagsCalls = [];

  @override
  Future<void> reloadFeatureFlags() async {
    reloadFeatureFlagsCount++;
  }

  @override
  Future<void> setPersonPropertiesForFlags(
    Map<String, Object> userProperties,
  ) async {
    setPersonPropertiesForFlagsCalls.add(userProperties);
  }

  @override
  Future<void> resetPersonPropertiesForFlags() async {
    resetPersonPropertiesForFlagsCount++;
  }

  @override
  Future<void> setGroupPropertiesForFlags(
    String groupType,
    Map<String, Object> groupProperties,
  ) async {
    setGroupPropertiesForFlagsCalls.add({
      'groupType': groupType,
      'groupProperties': groupProperties,
    });
  }

  @override
  Future<void> resetGroupPropertiesForFlags({String? groupType}) async {
    resetGroupPropertiesForFlagsCalls.add(groupType);
  }

  // Tracking for captureLog calls (after Dart-side beforeSend has run)
  final List<CapturedLogCall> capturedLogs = [];

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    this.screenName = screenName;
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
    capturedLogs.add(
      CapturedLogCall(
        body: body,
        level: level,
        attributes: attributes,
        traceId: traceId,
        spanId: spanId,
        traceFlags: traceFlags,
      ),
    );
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
    capturedExceptions.add(
      CapturedExceptionCall(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
      ),
    );
  }

  // Tracking for addExceptionStep calls
  final List<Map<String, Object?>> addExceptionStepCalls = [];

  @override
  Future<void> addExceptionStep(
    String message, {
    Map<String, Object>? properties,
  }) async {
    addExceptionStepCalls.add({
      'message': message,
      'properties': properties,
    });
  }

  @override
  Future<void> disable() async {}

  @override
  Future<void> enable() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
  }) async {
    setPersonPropertiesCalls.add({
      'userPropertiesToSet': userPropertiesToSet,
      'userPropertiesToSetOnce': userPropertiesToSetOnce,
    });
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
    final enabled = value != null && value != false;
    final variant = (value is String) ? value : null;
    return PostHogFeatureFlagResult(
      key: key,
      enabled: enabled,
      variant: variant,
      payload: payload,
    );
  }
}
