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
  // Routes through posthog-js's error pipeline so required metadata and
  // $exception_steps attach. The call site guards with try/catch.
  external JSAny? captureException(JSAny? error, JSAny? additionalProperties);
  // May be absent on older posthog-js builds; the call site guards with try/catch.
  external void captureLog(JSAny options);
  // May be absent on older posthog-js builds; the call site guards with try/catch.
  external void addExceptionStep(JSAny message, JSAny? properties);
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
  external void setPersonPropertiesForFlags(
    JSAny properties,
    JSAny reloadFeatureFlags,
  );
  external void resetPersonPropertiesForFlags();
  external void setGroupPropertiesForFlags(
    JSAny properties,
    JSAny reloadFeatureFlags,
  );
  external void resetGroupPropertiesForFlags(JSAny? groupType);
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

// The human-readable message used only as the posthog-js captureException
// trigger; its parse is overridden by the Dart-built properties we pass as
// additionalProperties. Read from the exception list the Dart side builds.
String _exceptionMessage(Map<String, Object?> properties) {
  final exceptionList = properties[r'$exception_list'];
  if (exceptionList is List && exceptionList.isNotEmpty) {
    final first = exceptionList.first;
    if (first is Map) {
      final value = first['value'];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
  }
  return 'Exception';
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
    case 'captureLog':
      final body = args['body'] as String;
      final level = args['level'] as String? ?? 'info';
      final attributes = safeMapConversion(args['attributes']);
      final traceId = args['traceId'] as String?;
      final spanId = args['spanId'] as String?;
      final traceFlags = args['traceFlags'] as int?;

      // posthog-js captureLog options. See https://posthog.com/docs/logs
      final options = <String, Object>{
        'body': body,
        'level': level,
        if (attributes.isNotEmpty) 'attributes': attributes,
        if (traceId != null) 'trace_id': traceId,
        if (spanId != null) 'span_id': spanId,
        // trace_flags 0 is meaningful (W3C sampled-false); only omit when null.
        if (traceFlags != null) 'trace_flags': traceFlags,
      };

      try {
        posthog?.captureLog(mapToJSAny(options));
      } catch (error) {
        // Older posthog-js builds lack captureLog and throw.
        printIfDebug(
          '[PostHog] captureLog is not supported by the loaded posthog-js version: $error',
        );
      }
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
    case 'setPersonPropertiesForFlags':
      final userProperties = safeMapConversion(args['userProperties']);
      // reload is orchestrated by the Dart layer, so disable it here.
      posthog?.setPersonPropertiesForFlags(
        mapToJSAny(userProperties),
        boolToJSAny(false),
      );
      break;
    case 'resetPersonPropertiesForFlags':
      posthog?.resetPersonPropertiesForFlags();
      break;
    case 'setGroupPropertiesForFlags':
      final groupType = args['groupType'] as String;
      final groupProperties = safeMapConversion(args['groupProperties']);
      // posthog-js expects an object keyed by group type.
      // reload is orchestrated by the Dart layer, so disable it here.
      posthog?.setGroupPropertiesForFlags(
        mapToJSAny({groupType: groupProperties}),
        boolToJSAny(false),
      );
      break;
    case 'resetGroupPropertiesForFlags':
      final groupType = args['groupType'] as String?;
      posthog?.resetGroupPropertiesForFlags(
        groupType != null ? stringToJSAny(groupType) : null,
      );
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
    case 'addExceptionStep':
      final message = args['message'] as String;
      final properties = safeMapConversion(args['properties']);

      try {
        posthog?.addExceptionStep(
          stringToJSAny(message),
          properties.isNotEmpty ? mapToJSAny(properties) : null,
        );
      } catch (error) {
        // Older posthog-js builds lack addExceptionStep and throw.
        printIfDebug(
          '[PostHog] addExceptionStep is not supported by the loaded posthog-js version: $error',
        );
      }
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
      // The platform interface sends a Map ({'resumeCurrent': bool}). Fall back
      // to the legacy bool shape so older callers keep working.
      final bool resumeCurrent;
      if (args is Map) {
        resumeCurrent = args['resumeCurrent'] as bool? ?? true;
      } else {
        resumeCurrent = args as bool? ?? true;
      }
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

      // Route through posthog-js's captureException so it attaches required
      // metadata and any buffered $exception_steps. posthog-js spreads the
      // additionalProperties last, so our Dart-built $exception_list (frames,
      // mechanism.handled, level) overrides its synthetic parse of `message`.
      try {
        posthog?.captureException(
          stringToJSAny(_exceptionMessage(properties)),
          mapToJSAny(properties),
        );
      } catch (error) {
        // Very old posthog-js lacks captureException; still record the event.
        printIfDebug(
          '[PostHog] captureException via posthog-js failed; falling back to capture: $error',
        );
        posthog?.capture(
          stringToJSAny('\$exception'),
          mapToJSAny(properties),
          null,
        );
      }
      break;
    default:
      throw PlatformException(
        code: 'Unimplemented',
        details:
            "The posthog plugin for web doesn't implement the method '${call.method}'",
      );
  }
}
