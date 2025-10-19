import 'package:stack_trace/stack_trace.dart';
import 'utils/isolate_utils.dart' as isolate_utils;

class DartExceptionProcessor {
  /// Converts Dart error/exception and stack trace to PostHog exception format
  static Map<String, dynamic> processException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
    bool handled = true,
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
    StackTrace Function()? stackTraceProvider, //for testing
  }) {
    StackTrace? effectiveStackTrace = stackTrace;
    bool isGeneratedStackTrace = false;

    // If it's an Error, try to use its built-in stackTrace
    if (error is Error) {
      effectiveStackTrace ??= error.stackTrace;
    }

    // If still null or empty, get current stack trace
    if (effectiveStackTrace == null ||
        effectiveStackTrace == StackTrace.empty) {
      effectiveStackTrace = stackTraceProvider?.call() ?? StackTrace.current;
      isGeneratedStackTrace = true; // Flag to remove top PostHog frames
    }

    // Process single exception (Dart doesn't provide standard exception chaining afaik)
    final frames = _parseStackTrace(
      effectiveStackTrace,
      inAppIncludes: inAppIncludes,
      inAppExcludes: inAppExcludes,
      inAppByDefault: inAppByDefault,
      removeTopPostHogFrames: isGeneratedStackTrace,
    );

    final errorType = _getExceptionType(error);

    // we consider primitives and generated Strack traces as synthetic
    final exceptionData = <String, dynamic>{
      'type': errorType ?? 'Error',
      'mechanism': {
        'handled': handled,
        'synthetic': errorType == null || isGeneratedStackTrace,
        'type': 'generic',
      }
    };

    // Add exception message, if available
    final errorMessage = error.toString();
    if (errorMessage.isNotEmpty) {
      exceptionData['value'] = errorMessage;
    }

    // Add package from first stack frame (where exception was thrown)
    final exceptionPackage = _getExceptionPackage(effectiveStackTrace);
    if (exceptionPackage != null && exceptionPackage.isNotEmpty) {
      exceptionData['package'] = exceptionPackage;
    }

    // Add stacktrace, if any frames are available
    if (frames.isNotEmpty) {
      exceptionData['stacktrace'] = {
        'frames': frames,
        'type': 'raw',
      };
    }

    // Add thread ID, if available
    final threadId = _getCurrentThreadId();
    if (threadId != null) {
      exceptionData['thread_id'] = threadId;
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

  /// Determines if a stack frame belongs to PostHog SDK (just check package for now)
  static bool _isPostHogFrame(Frame frame) {
    return frame.package == 'posthog_flutter';
  }

  /// Parses stack trace into PostHog format
  static List<Map<String, dynamic>> _parseStackTrace(
    StackTrace stackTrace, {
    List<String>? inAppIncludes,
    List<String>? inAppExcludes,
    bool inAppByDefault = true,
    bool removeTopPostHogFrames = false,
  }) {
    final chain = Chain.forTrace(stackTrace);
    final frames = <Map<String, dynamic>>[];

    for (final trace in chain.traces) {
      bool skipNextPostHogFrame = removeTopPostHogFrames;

      for (final frame in trace.frames) {
        // Skip top PostHog frames?
        if (skipNextPostHogFrame) {
          if (_isPostHogFrame(frame)) {
            continue;
          }
          skipNextPostHogFrame = false;
        }

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
    final frameData = <String, dynamic>{
      'platform': 'dart',
      'abs_path': _extractAbsolutePath(frame),
      'in_app': _isInAppFrame(
        frame,
        inAppIncludes: inAppIncludes,
        inAppExcludes: inAppExcludes,
        inAppByDefault: inAppByDefault,
      ),
    };

    // add package, if available
    final package = _extractPackage(frame);
    if (package != null && package.isNotEmpty) {
      frameData['package'] = package;
    }

    // add function, if available
    final member = frame.member;
    if (member != null && member.isNotEmpty) {
      frameData['function'] = member;
    }

    // Add filename, if available
    final fileName = _extractFileName(frame);
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

  static String? _extractPackage(Frame frame) {
    return frame.package;
  }

  static String? _extractFileName(Frame frame) {
    return frame.uri.pathSegments.isNotEmpty
        ? frame.uri.pathSegments.last
        : null;
  }

  static String _extractAbsolutePath(Frame frame) {
    // For privacy, only return filename for local file paths
    if (frame.uri.scheme != 'dart' &&
        frame.uri.scheme != 'package' &&
        frame.uri.pathSegments.isNotEmpty) {
      return frame.uri.pathSegments.last; // Just filename for privacy
    }

    // For dart: and package: URIs, full path is safe
    return frame.uri.toString();
  }

  /// Extracts the package name from the first stack frame
  /// This is more accurate than guessing from exception type
  static String? _getExceptionPackage(StackTrace stackTrace) {
    try {
      final chain = Chain.forTrace(stackTrace);

      // Get the first frame from the first trace (where exception was thrown)
      if (chain.traces.isNotEmpty && chain.traces.first.frames.isNotEmpty) {
        final firstFrame = chain.traces.first.frames.first;
        return _extractPackage(firstFrame);
      }
    } catch (e) {
      // If stack trace parsing fails, return null
    }

    return null;
  }

  /// Gets the current thread ID using isolate-based detection
  static int? _getCurrentThreadId() {
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

      return null;
    } catch (e) {
      return null;
    }
  }

  static String? _getExceptionType(Object error) {
    // The string is only intended for providing information to a reader while debugging. There is no guaranteed format, the string value returned for a Type instances is entirely implementation dependent.
    final type = error.runtimeType.toString();
    return type.isNotEmpty ? type : null;
  }
}
