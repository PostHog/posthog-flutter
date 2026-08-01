import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/src/util/logging.dart';

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
/// }, intervalOf: () => const Duration(seconds: 1));
///
/// changeDetector.start();
/// ```
///
/// **Note:** Since the `onChange` callback is called periodically, ensure that
/// the operations performed are efficient to avoid impacting app performance.
class ChangeDetector {
  final VoidCallback onChange;

  /// Resolved before each poll is armed, so a config change (e.g. a
  /// close()/setup() reconfigure with a new throttleDelay) takes effect on
  /// the next tick without rebuilding the detector.
  final Duration Function() intervalOf;

  bool _isRunning = false;
  Timer? _timer;
  Duration _lastInterval = const Duration(seconds: 1);

  bool hasCapturedPlatformViews = false;

  /// While a native occlusion episode owns the replay, forcing frames would
  /// make the hidden Flutter tree re-render every tick only for the capture
  /// to be discarded.
  bool suppressForcedFrames = false;

  bool get isRunning => _isRunning;

  /// Creates a [ChangeDetector] with the given [onChange] callback.
  ///
  /// [intervalOf] is consulted before each poll and controls how often to
  /// check for changes.
  ChangeDetector(this.onChange, {required this.intervalOf});

  /// Starts the change detection process.
  ///
  /// This method schedules periodic checks that trigger the [onChange] callback
  /// after the next frame is rendered.
  void start() {
    if (_isRunning) {
      return;
    }

    _isRunning = true;
    // Force the first frame: on a static screen nothing else schedules one,
    // and without a rendered frame the post-frame callback (and so the first
    // capture) would never run.
    _scheduleFrameCallback(forceFrame: true);
    _armTimer();
  }

  /// Stops the change detection process.
  ///
  /// This prevents the [onChange] callback from being called.
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  void _armTimer() {
    _timer = Timer(_resolveInterval(), () {
      if (!_isRunning) {
        return;
      }
      // Defensive: re-arm before doing anything that could throw. A throw here
      // would otherwise leave the chain dead with _isRunning still true, which
      // makes start() a no-op forever.
      _armTimer();
      try {
        _scheduleFrameCallback();
      } catch (error) {
        printIfDebug('Error scheduling change detection frame: $error');
      }
    });
  }

  /// Never throws: [intervalOf] comes from the host app's config, and a broken
  /// one must neither stop polling nor surface in the app's zone.
  Duration _resolveInterval() {
    try {
      return _lastInterval = intervalOf();
    } catch (error) {
      printIfDebug('Error resolving the change detection interval: $error');
      return _lastInterval;
    }
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
