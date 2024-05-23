// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

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
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    return handleWebMethodCall(call, globalContext);
  }
}
