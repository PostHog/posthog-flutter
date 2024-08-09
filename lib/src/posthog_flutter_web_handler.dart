import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/services.dart';

Future<dynamic> handleWebMethodCall(MethodCall call, JSObject context) async {
  final JSObject analytics = context.getProperty('posthog'.toJS)!;
  switch (call.method) {
    case 'identify':
      final userProperties = call.arguments['userProperties'] ?? {};
      final userPropertiesSetOnce =
          call.arguments['userPropertiesSetOnce'] ?? {};
      analytics.callMethodVarArgs('identify'.toJS, [
        (call.arguments['userId'] as String).toJS,
        userProperties.jsify(),
        userPropertiesSetOnce.jsify(),
      ]);
      break;
    case 'capture':
      final properties = call.arguments['properties'] ?? {};
      analytics.callMethodVarArgs('capture'.toJS, [
        (call.arguments['eventName'] as String).toJS,
        properties.jsify(),
      ]);
      break;
    case 'screen':
      final properties = call.arguments['properties'] ?? {};
      final screenName = call.arguments['screenName'];
      properties['\$screen_name'] = screenName;

      analytics.callMethodVarArgs('capture'.toJS, [
        '\$screen'.toJS,
        properties.jsify(),
      ]);
      break;
    case 'alias':
      analytics.callMethodVarArgs('alias'.toJS, [
        (call.arguments['alias'] as String).toJS,
      ]);
      break;
    case 'distinctId':
      final distinctId = analytics.callMethod('get_distinct_id'.toJS);
      return distinctId?.dartify();
    case 'reset':
      analytics.callMethod('reset'.toJS);
      break;
    case 'debug':
      analytics.callMethodVarArgs('debug'.toJS, [
        call.arguments['debug'].toJS,
      ]);
      break;
    case 'isFeatureEnabled':
      final isFeatureEnabled =
          analytics.callMethodVarArgs('isFeatureEnabled'.toJS, [
        (call.arguments['key'] as String).toJS,
      ]);
      return isFeatureEnabled;
    case 'group':
      analytics.callMethodVarArgs('group'.toJS, [
        call.arguments['groupType'].toJS,
        call.arguments['groupKey'].toJS,
        (call.arguments['groupProperties'] ?? {}).jsify(),
      ]);
      break;
    case 'reloadFeatureFlags':
      analytics.callMethod('reloadFeatureFlags'.toJS);
      break;
    case 'enable':
      analytics.callMethod('opt_in_capturing'.toJS);
      break;
    case 'disable':
      analytics.callMethod('opt_out_capturing'.toJS);
      break;
    case 'getFeatureFlag':
      final featureFlag = analytics.callMethodVarArgs('getFeatureFlag'.toJS, [
        call.arguments['key'].toJS,
      ]);
      return featureFlag;
    case 'getFeatureFlagPayload':
      final featureFlag =
          analytics.callMethodVarArgs('getFeatureFlagPayload'.toJS, [
        call.arguments['key'].toJS,
      ]);
      return featureFlag?.dartify();
    case 'register':
      final properties = {call.arguments['key']: call.arguments['value']};
      analytics.callMethodVarArgs('register'.toJS, [
        properties.jsify(),
      ]);
      break;
    case 'unregister':
      analytics.callMethodVarArgs('unregister'.toJS, [
        call.arguments['key'].toJS,
      ]);
      break;
    case 'flush':
      // not supported on Web
      // analytics.callMethod('flush');
      break;
    default:
      throw PlatformException(
        code: 'Unimplemented',
        details:
            "The posthog plugin for web doesn't implement the method '${call.method}'",
      );
  }
}
