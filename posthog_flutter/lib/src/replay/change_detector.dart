import 'dart:async';

import 'package:flutter/widgets.dart';

/// A class that detects changes in the UI and executes a callback when changes occur.
///
/// The `ChangeDetector` monitors the Flutter widget tree by scheduling
/// a callback after a frame is rendered. To avoid unnecessary overhead,
/// it only listens for frame callbacks while actively polling at a fixed interval.
///
/// **Usage:**
/// ```dart
/// final changeDetector = ChangeDetector(() {
///   // Code to execute when a UI change is detected.
///   print('UI has updated.');
/// });
///
/// changeDetector.start();
/// ```
///
/// **Note:** Since the `onChange` callback is called periodically, ensure that
/// the operations performed are efficient to avoid impacting app performance.
class ChangeDetector {
  final VoidCallback onChange;
  final Duration interval;
  bool _isRunning = false;
  Timer? _timer;

  /// Creates a [ChangeDetector] with the given [onChange] callback.
  ///
  /// [interval] controls how often to check for changes.
  ChangeDetector(this.onChange, {this.interval = const Duration(seconds: 1)});

  /// Starts the change detection process.
  ///
  /// This method schedules periodic checks that trigger the [onChange] callback
  /// after the next frame is rendered.
  void start() {
    if (_isRunning) {
      return;
    }

    _isRunning = true;
    _scheduleFrameCallback();
    _timer = Timer.periodic(interval, (_) {
      _scheduleFrameCallback();
    });
  }

  /// Stops the change detection process.
  ///
  /// This prevents the [onChange] callback from being called.
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Schedules a single post-frame callback to invoke [onChange].
  void _scheduleFrameCallback() {
    if (!_isRunning) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isRunning) {
        onChange();
      }
    });
  }
}
