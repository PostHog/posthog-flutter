// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
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

  Future<dynamic> handleMethodCall(MethodCall call) async {
    final analytics = JsObject.fromBrowserObject(context['posthog']);
    switch (call.method) {
      case 'identify':
        final userProperties = call.arguments['userProperties'];
        final userPropertiesSetOnce = call.arguments['userPropertiesSetOnce'];
        analytics.callMethod('identify', [
          call.arguments['userId'],
          JsObject.jsify(userProperties),
          JsObject.jsify(userPropertiesSetOnce),
        ]);
        break;
      case 'capture':
        analytics.callMethod('capture', [
          call.arguments['eventName'],
          JsObject.jsify(call.arguments['properties']),
        ]);
        break;
      case 'screen':
        final properties = call.arguments['properties'] ?? {};
        final screenName = call.arguments['screenName'];
        if (screenName != null) {
          properties['\$screen_name'] = screenName;
        }
        analytics.callMethod('capture', [
          '\$screen',
          JsObject.jsify(properties),
        ]);
        break;
      case 'alias':
        analytics.callMethod('alias', [
          call.arguments['alias'],
        ]);
        break;
      case 'distinctId':
        final distinctId = analytics.callMethod('get_distinct_id');
        return distinctId;
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
        analytics.callMethod('getFeatureFlag', [
          call.arguments['key'],
        ]);
        break;
      case 'getFeatureFlagPayload':
        analytics.callMethod('getFeatureFlagPayload', [
          call.arguments['key'],
        ]);
        break;
      case 'register':
        final properties = {call.arguments['key']: call.arguments['value']};
        analytics.callMethod('register', [
          properties,
        ]);
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
