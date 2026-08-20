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
  int _forcedTicksLeft = 0;

  bool hasCapturedPlatformViews = false;

  /// While a native occlusion episode owns the replay, forcing frames would
  /// make the hidden Flutter tree re-render every tick only for the capture
  /// to be discarded.
  bool suppressForcedFrames = false;

  bool get isRunning => _isRunning;

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
    // A pending budget means a session boundary armed it, and forcing a frame
    // now would record the screen the host has not replaced yet. Leave that
    // first frame to the budget's own ticks. Any other start() — app launch, a
    // recording resumed on the same session — still forces, or a static screen
    // would record nothing until it happens to repaint.
    if (_forcedTicksLeft > 0) {
      _scheduleFrameCallback();
    } else {
      requestImmediateSample();
    }
    _timer = Timer.periodic(interval, (_) {
      final forceFrame = _forcedTicksLeft > 0;
      if (forceFrame) {
        _forcedTicksLeft--;
      }
      _scheduleFrameCallback(forceFrame: forceFrame);
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

  /// Keeps forcing a frame for up to [count] further poll ticks.
  ///
  /// One forced sample is not enough after a session change: iOS reports replay
  /// inactive for ~120 ms after `reset()` while its flags reload, so the sample
  /// is spent on a tick that captures nothing.
  ///
  /// Only delivery clears the budget, never [stop] — `close()` arms it and the
  /// following `setup()` is what spends it.
  void forceNextTicks(int count) {
    _forcedTicksLeft = count;
  }

  /// Drops any retries armed by [forceNextTicks].
  void cancelForcedTicks() {
    _forcedTicksLeft = 0;
  }

  /// Samples once before the next poll tick. A static screen renders no frame on
  /// its own, so without forcing one the post-frame callback never runs.
  ///
  /// Forces nothing while [suppressForcedFrames] is set, so a caller ending a
  /// suppressed episode must clear that flag first.
  void requestImmediateSample() {
    _scheduleFrameCallback(forceFrame: true);
  }

  /// Schedules a single post-frame callback to invoke [onChange].
  void _scheduleFrameCallback({bool forceFrame = false}) {
    if (!_isRunning) {
      return;
    }

    if ((forceFrame || hasCapturedPlatformViews) && !suppressForcedFrames) {
      WidgetsBinding.instance.scheduleFrame();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isRunning) {
        onChange();
      }
    });
  }
}
