import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

class PosthogFlutterPlatformFake extends PosthogFlutterPlatformInterface {
  String? screenName;

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    this.screenName = screenName;
  }
}
