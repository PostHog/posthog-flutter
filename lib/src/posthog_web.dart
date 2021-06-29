import 'dart:js';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart' show Registrar;

class PosthogWeb {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'posthogflutter',
      const StandardMethodCodec(),
      registrar.messenger,
    );
    final PosthogWeb instance = PosthogWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);
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
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: "The posthog plugin for web doesn't implement the method '${call.method}'",
        );
    }
  }
}
