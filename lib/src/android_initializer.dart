import 'package:flutter/services.dart';
import 'package:posthog_flutter/src/posthog_options.dart';

import 'platform_initializer.dart';

class AndroidInitializer implements PlatformInitializer {
  static const MethodChannel _channel = MethodChannel('posthog_flutter');

  @override
  Future<void> init(String apiKey, PostHogOptions options) async {

    if (options.enableSessionReplay){
      setDefaultDebouncerDelay(options);
    }

    final Map<String, dynamic> configMap = {
      'apiKey': apiKey,
      'options': options.toMap(),
    };

    try {
      await _channel.invokeMethod('initNativeSdk', configMap);
    } on PlatformException catch (e) {
      print('Failed to initialize PostHog on Android: ${e.message}');
    }
  }

  void setDefaultDebouncerDelay(PostHogOptions options){
    options.sessionReplayConfig?.androidDebouncerDelay ??= const Duration(milliseconds: 200);
  }
}
