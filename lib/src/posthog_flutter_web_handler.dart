import 'dart:js_interop';

import 'package:flutter/services.dart';

// Definition of the JS interface for PostHog
@JS()
@staticInterop
class PostHog {}

extension PostHogExtension on PostHog {
  external JSAny? identify(
      JSAny userId, JSAny properties, JSAny propertiesSetOnce);
  external JSAny? capture(JSAny eventName, JSAny properties);
  external JSAny? alias(JSAny alias);
  // ignore: non_constant_identifier_names
  external JSAny? get_distinct_id();
  external void reset();
  external void debug(JSAny debug);
  external JSAny? isFeatureEnabled(JSAny key);
  external void group(JSAny type, JSAny key, JSAny properties);
  external void reloadFeatureFlags();
  // ignore: non_constant_identifier_names
  external void opt_in_capturing();
  // ignore: non_constant_identifier_names
  external void opt_out_capturing();
  external JSAny? getFeatureFlag(JSAny key);
  external JSAny? getFeatureFlagPayload(JSAny key);
  external void register(JSAny properties);
  external void unregister(JSAny key);
  // ignore: non_constant_identifier_names
  external JSAny? get_session_id();
}

// Accessing PostHog from the window object
@JS('window.posthog')
external PostHog? get posthog;

// Conversion functions
JSAny stringToJSAny(String value) {
  return value.toJS;
}

JSAny boolToJSAny(bool value) {
  return value.toJS;
}

JSAny mapToJSAny(Map<dynamic, dynamic> map) {
  return map.jsify() ?? JSObject();
}

// Function for safely converting maps
Map<String, dynamic> safeMapConversion(dynamic mapData) {
  if (mapData == null) {
    return {};
  }

  if (mapData is Map) {
    return Map<String, dynamic>.from(
        mapData.map((key, value) => MapEntry(key.toString(), value)));
  }

  return {};
}

Future<dynamic> handleWebMethodCall(MethodCall call) async {
  final args = call.arguments;

  switch (call.method) {
    case 'setup':
      // not supported on Web
      break;
    case 'identify':
      final userId = args['userId'] as String;
      final userProperties = safeMapConversion(args['userProperties']);
      final userPropertiesSetOnce =
          safeMapConversion(args['userPropertiesSetOnce']);

      posthog?.identify(
        stringToJSAny(userId),
        mapToJSAny(userProperties),
        mapToJSAny(userPropertiesSetOnce),
      );
      break;
    case 'capture':
      final eventName = args['eventName'] as String;
      final properties = safeMapConversion(args['properties']);

      posthog?.capture(
        stringToJSAny(eventName),
        mapToJSAny(properties),
      );
      break;
    case 'screen':
      final screenName = args['screenName'] as String;
      final properties = safeMapConversion(args['properties']);
      properties['\$screen_name'] = screenName;

      posthog?.capture(
        stringToJSAny('\$screen'),
        mapToJSAny(properties),
      );
      break;
    case 'alias':
      final alias = args['alias'] as String;

      posthog?.alias(
        stringToJSAny(alias),
      );
      break;
    case 'distinctId':
      final distinctId = posthog?.get_distinct_id();
      return distinctId?.dartify() as String?;
    case 'reset':
      posthog?.reset();
      break;
    case 'debug':
      final enabled = args['debug'] as bool;
      posthog?.debug(boolToJSAny(enabled));
      break;
    case 'isFeatureEnabled':
      final key = args['key'] as String;
      final isFeatureEnabled = posthog
              ?.isFeatureEnabled(
                stringToJSAny(key),
              )
              ?.dartify() as bool? ??
          false;
      return isFeatureEnabled;
    case 'group':
      final groupType = args['groupType'] as String;
      final groupKey = args['groupKey'] as String;
      final groupProperties = safeMapConversion(args['groupProperties']);

      posthog?.group(
        stringToJSAny(groupType),
        stringToJSAny(groupKey),
        mapToJSAny(groupProperties),
      );
      break;
    case 'reloadFeatureFlags':
      posthog?.reloadFeatureFlags();
      break;
    case 'enable':
      posthog?.opt_in_capturing();
      break;
    case 'disable':
      posthog?.opt_out_capturing();
      break;
    case 'getFeatureFlag':
      final key = args['key'] as String;

      final featureFlag = posthog?.getFeatureFlag(
        stringToJSAny(key),
      );
      return featureFlag?.dartify();
    case 'getFeatureFlagPayload':
      final key = args['key'] as String;

      final featureFlag = posthog?.getFeatureFlagPayload(
        stringToJSAny(key),
      );
      return featureFlag?.dartify();
    case 'register':
      final key = args['key'] as String;
      final value = args['value'];
      final properties = {key: value};

      posthog?.register(
        mapToJSAny(properties),
      );
      break;
    case 'unregister':
      final key = args['key'] as String;

      posthog?.unregister(
        stringToJSAny(key),
      );
      break;
    case 'getSessionId':
      final sessionId = posthog?.get_session_id()?.dartify() as String?;
      if (sessionId?.isEmpty == true) return null;
      return sessionId;
    case 'flush':
      // not supported on Web
      // analytics.callMethod('flush');
      break;
    case 'close':
      // not supported on Web
      // analytics.callMethod('close');
      break;
    case 'sendMetaEvent':
      // not supported on Web
      // Flutter Web uses the JS SDK for Session replay
      break;
    case 'sendFullSnapshot':
      // not supported on Web
      // Flutter Web uses the JS SDK for Session replay
      break;
    case 'isSessionReplayActive':
      // not supported on Web
      // Flutter Web uses the JS SDK for Session replay
      return false;
    case 'openUrl':
      // not supported on Web
      break;
    case 'surveyAction':
      // not supported on Web
      break;
    default:
      throw PlatformException(
        code: 'Unimplemented',
        details:
            "The posthog plugin for web doesn't implement the method '${call.method}'",
      );
  }
}
