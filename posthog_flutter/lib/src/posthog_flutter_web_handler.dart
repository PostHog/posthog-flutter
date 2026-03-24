// ignore_for_file: avoid_dynamic_calls, avoid_annotating_with_dynamic

import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';
import 'package:posthog_flutter/src/util/logging.dart';

import 'package:web/web.dart' as web;

// Definition of the JS interface for PostHog
@JS()
@staticInterop
class PostHog {}

extension PostHogExtension on PostHog {
  external JSAny? identify(
    JSAny userId,
    JSAny properties,
    JSAny propertiesSetOnce,
  );
  external JSAny? capture(JSAny eventName, JSAny? properties, JSAny? options);
  external JSAny? alias(JSAny alias);
  // ignore: non_constant_identifier_names
  external JSAny? get_distinct_id();
  external void reset();
  external void debug(JSAny debug);
  external JSAny? isFeatureEnabled(JSAny key);
  external void group(JSAny type, JSAny key, JSAny properties);
  external void reloadFeatureFlags();
  external void setPersonProperties(
    JSAny? userPropertiesToSet,
    JSAny? userPropertiesToSetOnce,
  );
  // ignore: non_constant_identifier_names
  external void opt_in_capturing();
  // ignore: non_constant_identifier_names
  external void opt_out_capturing();
  // ignore: non_constant_identifier_names
  external bool has_opted_out_capturing();
  external JSAny? getFeatureFlag(JSAny key);
  external JSAny? getFeatureFlagPayload(JSAny key);
  external JSAny? getFeatureFlagResult(JSAny key, [JSAny? options]);
  external void register(JSAny properties);
  external void unregister(JSAny key);
  // ignore: non_constant_identifier_names
  external JSAny? get_session_id();
  external void onFeatureFlags(JSFunction callback);
  external void startSessionRecording();
  external void stopSessionRecording();
  external bool sessionRecordingStarted();
  external SessionManager? get sessionManager;
  // ignore: non_constant_identifier_names
  external void _overrideSDKInfo(JSAny sdkName, JSAny sdkVersion);
}

// SessionManager JS interop
@JS()
@staticInterop
class SessionManager {}

extension SessionManagerExtension on SessionManager {
  external void resetSessionId();
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
      mapData.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  return {};
}

bool _sdkInfoOverridden = false;

void _maybeOverrideSDKInfo() {
  if (_sdkInfoOverridden) return;
  _sdkInfoOverridden = true;
  try {
    posthog?._overrideSDKInfo(
      stringToJSAny(postHogFlutterSdkName),
      stringToJSAny(postHogFlutterVersion),
    );
  } catch (error) {
    // The JS SDK version may not support _overrideSDKInfo yet
    printIfDebug(
        'Warning: Unable to override SDK info. Please ensure you are using posthog-js version 1.361.1 or later for better Flutter Web support., error: $error');
  }
}

Map<String, String> _getLocationProperties() {
  try {
    final location = web.window.location;
    return {
      '\$current_url': location.href,
      '\$host': location.host,
      '\$pathname': location.pathname,
    };
  } catch (_) {
    return {};
  }
}

Future<dynamic> handleWebMethodCall(MethodCall call) async {
  _maybeOverrideSDKInfo();

  final args = call.arguments;

  switch (call.method) {
    case 'setup':
      // not supported on Web
      break;
    case 'identify':
      final userId = args['userId'] as String;
      final userProperties = safeMapConversion(args['userProperties']);
      final userPropertiesSetOnce = safeMapConversion(
        args['userPropertiesSetOnce'],
      );

      posthog?.identify(
        stringToJSAny(userId),
        mapToJSAny(userProperties),
        mapToJSAny(userPropertiesSetOnce),
      );
      break;
    case 'setPersonProperties':
      final userPropertiesToSet = safeMapConversion(
        args['userPropertiesToSet'],
      );
      final userPropertiesToSetOnce = safeMapConversion(
        args['userPropertiesToSetOnce'],
      );

      posthog?.setPersonProperties(
        userPropertiesToSet.isNotEmpty ? mapToJSAny(userPropertiesToSet) : null,
        userPropertiesToSetOnce.isNotEmpty
            ? mapToJSAny(userPropertiesToSetOnce)
            : null,
      );
      break;
    case 'capture':
      final eventName = args['eventName'] as String;
      final properties = safeMapConversion(args['properties']);
      properties.addAll(_getLocationProperties());
      final userProperties = safeMapConversion(args['userProperties']);
      final userPropertiesSetOnce = safeMapConversion(
        args['userPropertiesSetOnce'],
      );

      // Build options object for posthog-js capture with $set and $set_once
      // See: https://github.com/PostHog/posthog-js/blob/main/packages/types/src/capture.ts
      final options = <String, Object>{};
      if (userProperties.isNotEmpty) {
        options['\$set'] = userProperties;
      }
      if (userPropertiesSetOnce.isNotEmpty) {
        options['\$set_once'] = userPropertiesSetOnce;
      }

      posthog?.capture(
        stringToJSAny(eventName),
        properties.isNotEmpty ? mapToJSAny(properties) : null,
        options.isNotEmpty ? mapToJSAny(options) : null,
      );
      break;
    case 'screen':
      final screenName = args['screenName'] as String;
      final properties = safeMapConversion(args['properties']);
      properties['\$screen_name'] = screenName;
      properties.addAll(_getLocationProperties());

      posthog?.capture(stringToJSAny('\$screen'), mapToJSAny(properties), null);
      break;
    case 'alias':
      final alias = args['alias'] as String;

      posthog?.alias(stringToJSAny(alias));
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
      final isFeatureEnabled =
          posthog?.isFeatureEnabled(stringToJSAny(key))?.dartify() as bool? ??
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
    case 'isOptOut':
      return posthog?.has_opted_out_capturing() ?? true;
    case 'getFeatureFlag':
      final key = args['key'] as String;

      final featureFlag = posthog?.getFeatureFlag(stringToJSAny(key));
      return featureFlag?.dartify();
    case 'getFeatureFlagPayload':
      final key = args['key'] as String;

      final featureFlag = posthog?.getFeatureFlagPayload(stringToJSAny(key));
      return featureFlag?.dartify();
    case 'getFeatureFlagResult':
      final key = args['key'] as String;
      final sendEvent = args['sendEvent'] as bool? ?? true;

      final result = posthog?.getFeatureFlagResult(
        stringToJSAny(key),
        {'send_event': sendEvent}.jsify(),
      );
      return result?.dartify();
    case 'register':
      final key = args['key'] as String;
      final value = args['value'];
      final properties = {key: value};

      posthog?.register(mapToJSAny(properties));
      break;
    case 'unregister':
      final key = args['key'] as String;

      posthog?.unregister(stringToJSAny(key));
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
      return posthog?.sessionRecordingStarted() ?? false;
    case 'startSessionRecording':
      final resumeCurrent = args as bool? ?? true;
      if (!resumeCurrent) {
        // Reset session ID to start a new session
        posthog?.sessionManager?.resetSessionId();
      }
      posthog?.startSessionRecording();
      break;
    case 'stopSessionRecording':
      posthog?.stopSessionRecording();
      break;
    case 'openUrl':
      // not supported on Web
      break;
    case 'surveyAction':
      // not supported on Web
      break;
    case 'captureException':
      final properties = safeMapConversion(args['properties']);
      properties.addAll(_getLocationProperties());

      posthog?.capture(
        stringToJSAny('\$exception'),
        mapToJSAny(properties),
        null,
      );
      break;
    default:
      throw PlatformException(
        code: 'Unimplemented',
        details:
            "The posthog plugin for web doesn't implement the method '${call.method}'",
      );
  }
}
