import 'dart:js';

import 'package:flutter/services.dart';

Future<dynamic> handleWebMethodCall(MethodCall call, JsObject context) async {
  final analytics = JsObject.fromBrowserObject(context['posthog']);
  switch (call.method) {
    case 'identify':
      final userProperties = call.arguments['userProperties'] ?? {};
      final userPropertiesSetOnce =
          call.arguments['userPropertiesSetOnce'] ?? {};
      analytics.callMethod('identify', [
        call.arguments['userId'],
        JsObject.jsify(userProperties),
        JsObject.jsify(userPropertiesSetOnce),
      ]);
      break;
    case 'capture':
      final properties = call.arguments['properties'] ?? {};
      analytics.callMethod('capture', [
        call.arguments['eventName'],
        JsObject.jsify(properties),
      ]);
      break;
    case 'screen':
      final properties = call.arguments['properties'] ?? {};
      final screenName = call.arguments['screenName'];
      properties['\$screen_name'] = screenName;

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
        JsObject.jsify(call.arguments['groupProperties'] ?? {}),
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
      final featureFlag = analytics.callMethod('getFeatureFlag', [
        call.arguments['key'],
      ]);
      return featureFlag;
    case 'getFeatureFlagPayload':
      final featureFlag = analytics.callMethod('getFeatureFlagPayload', [
        call.arguments['key'],
      ]);
      return featureFlag;
    case 'register':
      final properties = {call.arguments['key']: call.arguments['value']};
      analytics.callMethod('register', [
        JsObject.jsify(properties),
      ]);
      break;
    case 'unregister':
      analytics.callMethod('unregister', [
        call.arguments['key'],
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
