// Portions of this file are derived from getsentry/sentry-dart
// Copyright (c) 2020 Sentry
// Licensed under the MIT License: https://github.com/getsentry/sentry-dart/blob/main/LICENSE

import 'dart:isolate';

// ignore: unnecessary_import
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
