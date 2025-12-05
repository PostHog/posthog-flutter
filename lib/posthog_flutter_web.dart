// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/posthog_config.dart';
import 'src/posthog_flutter_platform_interface.dart';
import 'src/posthog_flutter_web_handler.dart';

/// A web implementation of the PosthogFlutterPlatform of the PosthogFlutter plugin.
class PosthogFlutterWeb extends PosthogFlutterPlatformInterface {
  /// Constructs a PosthogFlutterWeb
  PosthogFlutterWeb();

  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'posthog_flutter',
      const StandardMethodCodec(),
      registrar,
    );
    final PosthogFlutterWeb instance = PosthogFlutterWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);
    PosthogFlutterPlatformInterface.instance = instance;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    // The 'setup' call is now handled by the setup method override.
    // Other method calls are delegated to handleWebMethodCall.
    if (call.method == 'setup') {
      // This case should ideally not be hit if Posthog().setup directly calls the overridden setup.
      // However, to be safe, we can log or ignore.
      // For now, let's assume direct call to overridden setup handles it.
      return null;
    }
    return handleWebMethodCall(call);
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    // It's assumed posthog-js is initialized by the user in their HTML.
    // This setup primarily hooks into the existing posthog-js instance.

    // If apiKey and host are in config, and posthog.init is to be handled by plugin:
    // This is an example if we wanted the plugin to also call posthog.init()
    // final jsOptions = <String, dynamic>{
    //   'api_host': config.host,
    //   // Add other relevant options from PostHogConfig if needed for JS init
    // }.jsify();
    // posthog?.callMethod('init'.toJS, config.apiKey.toJS, jsOptions);

    if (config.onFeatureFlags != null && posthog != null) {
      final dartCallback = config.onFeatureFlags!;

      final jsCallback = (JSArray jsFlags, JSObject jsFlagVariants) {
        final List<String> flags = jsFlags.toDart.whereType<String>().toList();

        Map<String, dynamic> flagVariants = {};
        final dartVariantsMap =
            jsFlagVariants.dartify() as Map<dynamic, dynamic>?;
        if (dartVariantsMap != null) {
          flagVariants = dartVariantsMap
              .map((key, value) => MapEntry(key.toString(), value));
        }

        // When posthog-js onFeatureFlags fires, it implies successful loading.
        dartCallback(flags, flagVariants, errorsLoading: false);
      }.toJS;

      posthog!.onFeatureFlags(jsCallback);
    }
  }
}
