import 'dart:isolate';

import 'package:meta/meta.dart';

/// Native platform implementation of isolate error handling
@internal
class IsolateErrorHandler {
  RawReceivePort? _isolateErrorPort;

  /// Add error listener to current isolate (should be main isolate)
  void addErrorListener(Function(Object?) onError) {
    _isolateErrorPort = RawReceivePort(onError);
    final isolateErrorPort = _isolateErrorPort;
    if (isolateErrorPort != null) {
      Isolate.current.addErrorListener(isolateErrorPort.sendPort);
    }
  }

  /// Remove error listener and clean up
  void removeErrorListener() {
    final isolateErrorPort = _isolateErrorPort;
    if (isolateErrorPort != null) {
      isolateErrorPort.close();
      Isolate.current.removeErrorListener(isolateErrorPort.sendPort);
      _isolateErrorPort = null;
    }
  }

  /// Get current isolate name
  String? get isolateDebugName => Isolate.current.debugName;
}
