import 'package:stack_trace/stack_trace.dart';
import 'utils/isolate_utils.dart' as isolate_utils;

class DartExceptionProcessor {
  /// Converts Dart error/exception and stack trace to PostHog exception format
  static Map<String, dynamic> processException({
    required dynamic error,
    required StackTrace stackTrace,
    Map<String, Object>? properties,
    bool handled = true,
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
  }) {
    // Process single exception (Dart doesn't provide standard exception chaining afaik)
    final frames = _parseStackTrace(
      stackTrace,
      inAppIncludes: inAppIncludes,
      inAppExcludes: inAppExcludes,
      inAppByDefault: inAppByDefault,
    );

    final exceptionData = <String, dynamic>{
      'type': _getExceptionType(error),
      'mechanism': {
        'handled': handled,
        'synthetic': _isPrimitive(error), // we consider primitives as synthetic
        'type': 'generic',
      },
      'thread_id': _getCurrentThreadId(),
    };

    // Add exception message, if available
    final errorMessage = error.toString();
    if (errorMessage.isNotEmpty) {
      exceptionData['value'] = errorMessage;
    }

    // Add module/package from first stack frame (where exception was thrown)
    final exceptionModule = _getExceptionModule(stackTrace);
    if (exceptionModule != null && exceptionModule.isNotEmpty) {
      exceptionData['module'] = exceptionModule;
    }

    // Add stacktrace, if any frames are available
    if (frames.isNotEmpty) {
      exceptionData['stacktrace'] = {
        'frames': frames,
        'type': 'raw',
      };
    }

    final result = <String, dynamic>{
      '\$exception_level': handled ? 'error' : 'fatal',
      '\$exception_list': [exceptionData],
    };

    // Add custom properties if provided
    if (properties != null) {
      for (final entry in properties.entries) {
        // Don't allow overwriting system properties
        if (!result.containsKey(entry.key)) {
          result[entry.key] = entry.value;
        }
      }
    }

    return result;
  }

  /// Parses stack trace into PostHog format
  static List<Map<String, dynamic>> _parseStackTrace(
    StackTrace stackTrace, {
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
  }) {
    final chain = Chain.forTrace(stackTrace);
    final frames = <Map<String, dynamic>>[];

    for (final trace in chain.traces) {
      for (final frame in trace.frames) {
        final processedFrame = _convertFrameToPostHog(
          frame,
          inAppIncludes: inAppIncludes,
          inAppExcludes: inAppExcludes,
          inAppByDefault: inAppByDefault,
        );
        if (processedFrame != null) {
          frames.add(processedFrame);
        }
      }
    }

    return frames;
  }

  /// Converts a Frame from stack_trace package to PostHog format
  static Map<String, dynamic>? _convertFrameToPostHog(
    Frame frame, {
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
  }) {
    final member = frame.member;
    final fileName =
        frame.uri.pathSegments.isNotEmpty ? frame.uri.pathSegments.last : null;

    final frameData = <String, dynamic>{
      'function': member ?? 'unknown',
      'module': _extractModule(frame),
      'platform': 'dart',
      'in_app': _isInAppFrame(
        frame,
        inAppIncludes: inAppIncludes,
        inAppExcludes: inAppExcludes,
        inAppByDefault: inAppByDefault,
      ),
    };

    // Add filename, if available
    if (fileName != null && fileName.isNotEmpty) {
      frameData['filename'] = fileName;
    }

    // Add line number, if available
    final line = frame.line;
    if (line != null && line >= 0) {
      frameData['lineno'] = line;
    }

    // Add column number, if available
    final column = frame.column;
    if (column != null && column >= 0) {
      frameData['colno'] = column;
    }

    return frameData;
  }

  /// Determines if a frame is considered in-app
  static bool _isInAppFrame(
    Frame frame, {
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
  }) {
    final scheme = frame.uri.scheme;

    if (scheme.isEmpty) {
      // Early bail out for unknown schemes
      return inAppByDefault;
    }

    final package = frame.package;
    if (package != null) {
      // 1. Check inAppIncludes first (highest priority)
      if (inAppIncludes != null && inAppIncludes.contains(package)) {
        return true;
      }

      // 2. Check inAppExcludes second
      if (inAppExcludes != null && inAppExcludes.contains(package)) {
        return false;
      }
    }

    // 3. Hardcoded exclusions
    if (frame.isCore) {
      // dart: packages
      return false;
    }

    if (frame.package == 'flutter') {
      // flutter package
      return false;
    }

    // 4. Default fallback
    return inAppByDefault;
  }

  static String _extractModule(Frame frame) {
    final package = frame.package;
    if (package != null) {
      return package;
    }

    // For non-package files, extract from URI
    final pathSegments = frame.uri.pathSegments;
    if (pathSegments.length > 1) {
      return pathSegments[pathSegments.length - 2]; // Parent directory
    }

    return 'main';
  }

  /// Extracts the module/package name from the first stack frame
  /// This is more accurate than guessing from exception type
  static String? _getExceptionModule(StackTrace stackTrace) {
    try {
      final chain = Chain.forTrace(stackTrace);

      // Get the first frame from the first trace (where exception was thrown)
      if (chain.traces.isNotEmpty && chain.traces.first.frames.isNotEmpty) {
        final firstFrame = chain.traces.first.frames.first;
        return _extractModule(firstFrame);
      }
    } catch (e) {
      // If stack trace parsing fails, return null
    }

    return null;
  }

  /// Gets the current thread ID using isolate-based detection
  static int _getCurrentThreadId() {
    try {
      // Check if we're in the root isolate (main thread)
      if (isolate_utils.isRootIsolate()) {
        return 'main'.hashCode;
      }

      // For other isolates, use the isolate's debug name
      final isolateName = isolate_utils.getIsolateName();
      if (isolateName != null && isolateName.isNotEmpty) {
        return isolateName.hashCode;
      }

      // Fallback for unknown isolates
      return 1;
    } catch (e) {
      // Graceful fallback if isolate detection fails
      return 1;
    }
  }

  static String _getExceptionType(dynamic error) {
    // For primitives (String, int, bool, double, null, etc.), just use "Error"
    if (_isPrimitive(error)) {
      return 'Error';
    }

    return error.runtimeType.toString();
  }

  /// Checks if a value is a primitive type
  static bool _isPrimitive(dynamic value) {
    return value is bool ||
        value is int ||
        value is double ||
        value is num ||
        value is String;
  }
}
