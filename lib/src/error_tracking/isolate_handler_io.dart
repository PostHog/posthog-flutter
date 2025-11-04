import 'dart:isolate';

import 'package:posthog_flutter/src/util/logging.dart';

/// Native platform implementation of isolate error handling
class IsolateErrorHandler {
  RawReceivePort? _isolateErrorPort;

  /// Add error listener to current isolate (should be main isolate)
  void addErrorListener(Function(dynamic) onError) {
    // In Flutter, the main isolate typically has debugName 'main'
    final isolateName = Isolate.current.debugName;
    if (isolateName != null && isolateName != 'main') {
      printIfDebug(
          'PostHog isolate error handler is being set up in isolate "$isolateName" instead of main isolate');
    }

    _isolateErrorPort = RawReceivePort(onError);
    Isolate.current.addErrorListener(_isolateErrorPort!.sendPort);
  }

  /// Remove error listener and clean up
  void removeErrorListener() {
    if (_isolateErrorPort != null) {
      _isolateErrorPort!.close();
      Isolate.current.removeErrorListener(_isolateErrorPort!.sendPort);
      _isolateErrorPort = null;
    }
  }

  /// Check if error listener is active
  bool get isActive => _isolateErrorPort != null;
}
