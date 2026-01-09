// ignore_for_file: avoid_dynamic_calls, avoid_annotating_with_dynamic

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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
  // ignore: non_constant_identifier_names
  external bool has_opted_out_capturing();
  external JSAny? getFeatureFlag(JSAny key);
  external JSAny? getFeatureFlagPayload(JSAny key);
  external void register(JSAny properties);
  external void unregister(JSAny key);
  // ignore: non_constant_identifier_names
  external JSAny? get_session_id();
  external void onFeatureFlags(JSFunction callback);
}

// Accessing PostHog from the window object
@JS('window.posthog')
external PostHog? get posthog;

@JS('globalThis')
external JSObject get globalThis;

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

// Stack frame data structure
class StackFrame {
  final String? filename;
  final String? function;
  final int? lineno;
  final int? colno;
  final bool inApp;

  StackFrame({
    this.filename,
    this.function,
    this.lineno,
    this.colno,
    this.inApp = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'filename': filename,
      'function': function ?? '<anonymous>',
      'lineno': lineno,
      'colno': colno,
      'in_app': inApp,
    };
  }
}

// Stack line parser type
typedef StackLineParser = StackFrame? Function(String line, String platform);

// Chrome stack line parser
StackFrame? chromeStackLineParser(String line, String platform) {
  // Chrome regex patterns
  final chromeRegexNoFnName = RegExp(r'^\s*at\s+(\S+?)\s*:\s*(\d+)\s*:\s*(\d+)\s*$');
  final chromeRegex = RegExp(r'^\s*at\s+(?:(.+?)\s+)?\((?:address\s+at\s+)?(?:async\s+)?((?:<anonymous>|[-a-z]+:|.*bundle|\/)?.*?)(?::(\d+))?(?::(\d+))?\)?\s*$');
  final evalRegex = RegExp(r'\((\S*)(?::(\d+))(?::(\d+))\)');

  // Try no function name pattern first
  final noFnMatch = chromeRegexNoFnName.firstMatch(line);
  if (noFnMatch != null) {
    return StackFrame(
      filename: noFnMatch.group(1),
      function: '<anonymous>',
      lineno: int.tryParse(noFnMatch.group(2) ?? ''),
      colno: int.tryParse(noFnMatch.group(3) ?? ''),
    );
  }

  // Try full pattern
  final match = chromeRegex.firstMatch(line);
  if (match != null) {
    String? filename = match.group(2);
    String? functionName = match.group(1);
    int? lineno = int.tryParse(match.group(3) ?? '');
    int? colno = int.tryParse(match.group(4) ?? '');

    // Handle eval cases
    if (filename != null && filename.startsWith('eval')) {
      final evalMatch = evalRegex.firstMatch(filename);
      if (evalMatch != null) {
        filename = evalMatch.group(1);
        lineno = int.tryParse(evalMatch.group(2) ?? '');
        colno = int.tryParse(evalMatch.group(3) ?? '');
      }
    }

    // Extract safari extension details
    final safariDetails = extractSafariExtensionDetails(functionName ?? '<anonymous>', filename ?? '');
    functionName = safariDetails[0];
    filename = safariDetails[1];

    return StackFrame(
      filename: filename,
      function: functionName,
      lineno: lineno,
      colno: colno,
    );
  }

  return null;
}

// Gecko (Firefox) stack line parser
StackFrame? geckoStackLineParser(String line, String platform) {
  final geckoRegex = RegExp(r'^\s*(.*?)(?:\((.*?)\))?(?:^|@)?((?:[-a-z]+)?:\/.*?|\[native code\]|[^@]*(?:bundle|\d+\.js)|\/[\w\-\.\ \/=]+)(?::(\d+))?(?::(\d+))?\s*$');
  final geckoEvalRegex = RegExp(r'(\S+)\s+line\s+(\d+)(?:\s+>\s+eval\s+line\s+\d+)*\s+>\s+eval');

  final match = geckoRegex.firstMatch(line);
  if (match != null) {
    String? filename = match.group(3);
    String? functionName = match.group(1);
    int? lineno = int.tryParse(match.group(4) ?? '');
    int? colno = int.tryParse(match.group(5) ?? '');

    // Handle eval cases
    if (filename != null && filename.contains(' > eval')) {
      final evalMatch = geckoEvalRegex.firstMatch(filename);
      if (evalMatch != null) {
        functionName = functionName == '<anonymous>' || functionName == null ? 'eval' : functionName;
        filename = evalMatch.group(1);
        lineno = int.tryParse(evalMatch.group(2) ?? '');
        colno = null;
      }
    }

    // Extract safari extension details
    final safariDetails = extractSafariExtensionDetails(functionName ?? '<anonymous>', filename ?? '');
    functionName = safariDetails[0];
    filename = safariDetails[1];

    return StackFrame(
      filename: filename,
      function: functionName,
      lineno: lineno,
      colno: colno,
    );
  }

  return null;
}

// Extract Safari extension details (ported from JS)
List<String> extractSafariExtensionDetails(String functionName, String filename) {
  final isSafariExtension = filename.contains('safari-extension');
  final isSafariWebExtension = filename.contains('safari-web-extension');

  if (isSafariExtension || isSafariWebExtension) {
    final extractedFunction = filename.contains('@') ? filename.split('@')[0] : '<anonymous>';
    final prefix = isSafariExtension ? 'safari-extension:' : 'safari-web-extension:';
    return [extractedFunction, '$prefix$filename'];
  }

  return [functionName, filename];
}

// Create stack parser function
List<StackFrame> Function(String, [int]) createStackParser(String platform, List<StackLineParser> lineParsers) {
  return (String stack, [int skipLines = 0]) {
    final lines = stack.split('\n');
    final frames = <StackFrame>[];

    for (int i = skipLines; i < lines.length; i++) {
      final line = lines[i];

      // Skip lines over 1024 characters
      if (line.length > 1024) continue;

      // Skip lines that contain webpack error wrappers
      final cleanedLine = line.replaceFirst(RegExp(r'\(error: (.*)\)'), r'$1');

      // Skip "Error:" lines
      if (cleanedLine.contains(RegExp(r'\S*Error: '))) continue;

      // Try each parser
      for (final parser in lineParsers) {
        final frame = parser(cleanedLine, platform);
        if (frame != null) {
          frames.add(frame);
          break;
        }
      }

      // Limit to 50 frames
      if (frames.length >= 50) break;
    }

    // Reverse and process frames (like the original implementation)
    final reversedFrames = frames.reversed.toList();

    // Ensure each frame has a filename if possible
    for (int i = 0; i < reversedFrames.length; i++) {
      if (reversedFrames[i].filename == null && reversedFrames.isNotEmpty) {
        reversedFrames[i] = StackFrame(
          filename: reversedFrames.last.filename,
          function: reversedFrames[i].function,
          lineno: reversedFrames[i].lineno,
          colno: reversedFrames[i].colno,
          inApp: reversedFrames[i].inApp,
        );
      }
    }

    return reversedFrames.take(50).toList();
  };
}

// Create default stack parser
List<StackFrame> Function(String, [int]) createDefaultStackParser() {
  return createStackParser('web:javascript', [chromeStackLineParser, geckoStackLineParser]);
}

int _lastKeysCount = 0;
final Set<String> _chunkIdsWithFilenames = {};
final Map<String, String> _filenameToDebugIds = {};
// JSObject? _options;

// JSFunction? _stackParser(JSObject options) {
//   final parser = options['stackParser'];
//   if (parser != null && parser.isA<JSFunction>()) {
//     return parser as JSFunction;
//   }
//   return null;
// }

void _buildFilenameToDebugIdMapDart(
  Map<dynamic, dynamic> debugIdMap,
  List<StackFrame> Function(String, [int]) stackParser,
) {
  for (final debugIdMapEntry in debugIdMap.entries) {
    final String stackKeyStr = debugIdMapEntry.key.toString();
    final String debugIdStr = debugIdMapEntry.value.toString();

    final debugIdHasCachedFilename =
        _chunkIdsWithFilenames.contains(debugIdStr);

    if (!debugIdHasCachedFilename) {
      final parsedStack = stackParser(stackKeyStr);

      if (parsedStack.isEmpty) continue;

      for (final stackFrame in parsedStack) {
        final filename = stackFrame.filename;
        if (filename != null) {
          _filenameToDebugIds[filename] = debugIdStr;
          _chunkIdsWithFilenames.add(debugIdStr);
          break;
        }
      }
    }
  }
}

Map<String, String>? getPosthogChunkIds() {
  final debugIdMapJS = globalThis['_posthogChunkIds'];
  final debugIdMap = debugIdMapJS?.dartify() as Map<dynamic, dynamic>?;
  if (debugIdMap == null) {
    return null;
  }

  // Use our pure Dart implementation of createDefaultStackParser
  final stackParser = createDefaultStackParser();

  if (debugIdMap.keys.length != _lastKeysCount) {
    _buildFilenameToDebugIdMapDart(
      debugIdMap,
      stackParser,
    );
    _lastKeysCount = debugIdMap.keys.length;
  }

  return _filenameToDebugIds;
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
    case 'isOptOut':
      return posthog?.has_opted_out_capturing() ?? true;
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
    case 'captureException':
      final properties = safeMapConversion(args['properties']);
      // final timestamp = args['timestamp'] as int;

      posthog?.capture(
        stringToJSAny('\$exception'),
        mapToJSAny(properties),
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
