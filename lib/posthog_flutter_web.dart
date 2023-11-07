// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;
import 'dart:js';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'posthog_flutter_platform_interface.dart';

/// A web implementation of the PosthogFlutterPlatform of the PosthogFlutter plugin.
class PosthogFlutterWeb extends PosthogFlutterPlatform {
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

  /// Returns a [String] containing the version of the platform.
  @override
  Future<String?> getPlatformVersion() async {
    final version = html.window.navigator.userAgent;
    return version;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    final analytics = JsObject.fromBrowserObject(context['posthog']);
    switch (call.method) {
      case 'identify':
        analytics.callMethod('identify', [
          call.arguments['userId'],
          JsObject.jsify(call.arguments['properties']),
        ]);
        break;
      case 'capture':
        analytics.callMethod('capture', [
          call.arguments['eventName'],
          JsObject.jsify(call.arguments['properties']),
        ]);
        break;
      case 'screen':
        analytics.callMethod('capture', [
          call.arguments['screenName'],
          JsObject.jsify(call.arguments['properties']),
        ]);
        break;
      case 'alias':
        analytics.callMethod('alias', [
          call.arguments['alias'],
        ]);
        break;
      case 'getAnonymousId':
        final anonymousId = analytics.callMethod('get_distinct_id');
        return anonymousId;
      case 'reset':
        analytics.callMethod('reset');
        break;
      case 'debug':
        analytics.callMethod('debug', [
          call.arguments['debug'],
        ]);
        break;
      case 'isFeatureEnabled':
        final isFeatureEnabled = analytics.callMethod('isFeatureEnabled', [
          call.arguments['key'],
        ]);
        return isFeatureEnabled;
      case 'group':
        analytics.callMethod('group', [
          call.arguments['groupType'],
          call.arguments['groupKey'],
          JsObject.jsify(call.arguments['groupProperties']),
        ]);
        break;
      case 'reloadFeatureFlags':
        analytics.callMethod('reloadFeatureFlags');
        break;
      case 'enable':
        analytics.callMethod('opt_in_capturing');
        break;
      case 'disable':
        analytics.callMethod('opt_out_capturing');
        break;
      case 'getFeatureFlag':
        analytics.callMethod('getFeatureFlag');
        break;
      case 'getFeatureFlagPayload':
        analytics.callMethod('getFeatureFlagPayload');
        break;
      case 'getFeatureFlagAndPayload':
        analytics.callMethod('getFeatureFlagAndPayload');
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details:
              "The posthog plugin for web doesn't implement the method '${call.method}'",
        );
    }
  }
}
