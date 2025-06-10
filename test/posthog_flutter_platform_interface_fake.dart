import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

class PosthogFlutterPlatformFake extends PosthogFlutterPlatformInterface {
  String? screenName;
  OnFeatureFlagsCallback? registeredOnFeatureFlagsCallback;
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
}
