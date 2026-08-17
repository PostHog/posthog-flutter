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
/// }, intervalOf: () => const Duration(seconds: 1));
///
/// changeDetector.start();
/// ```
///
/// **Note:** Since the `onChange` callback is called periodically, ensure that
/// the operations performed are efficient to avoid impacting app performance.
class ChangeDetector {
  final VoidCallback onChange;

  /// Resolved once per [start]. The detector is stopped and restarted around
  /// every reconfigure, so reading it there is enough for a new throttleDelay
  /// to take effect; null means there is no config to poll for.
  final Duration? Function() intervalOf;

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
  /// [intervalOf] controls how often to check for changes.
  ChangeDetector(this.onChange, {required this.intervalOf});

  /// Starts the change detection process.
  ///
  /// This method schedules periodic checks that trigger the [onChange] callback
  /// after the next frame is rendered.
  void start() {
    if (_isRunning) {
      return;
    }
    final interval = intervalOf();
    if (interval == null) {
      return;
    }

    _isRunning = true;
    requestImmediateSample();
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
    _forcedTicksLeft = 0;
    _timer?.cancel();
    _timer = null;
  }

  /// Keeps forcing a frame for up to [count] further poll ticks, until
  /// [cancelForcedTicks] reports that a capture got through.
  ///
  /// A single forced sample is not enough after a session change: the platform
  /// can be transiently not recording when it lands, so the sample is spent on a
  /// tick that captures nothing, and on a static screen no later tick forces a
  /// frame. Observed on iOS, where `reset()` clears the remote config and
  /// `isSessionReplayActive()` requires the session-replay flag, which only
  /// returns once the flags reload lands. The retries cost nothing when the
  /// first sample does land — [cancelForcedTicks] drops them unused.
  void forceNextTicks(int count) {
    if (count > _forcedTicksLeft) {
      _forcedTicksLeft = count;
    }
  }

  /// Drops any retries armed by [forceNextTicks]; the capture they were covering
  /// for has landed.
  void cancelForcedTicks() {
    _forcedTicksLeft = 0;
  }

  /// Samples once before the next poll tick, forcing a frame so a static screen
  /// still gets sampled: nothing else schedules one there, and without a
  /// rendered frame the post-frame callback (and so the capture) never runs.
  ///
  /// No-ops while the detector is stopped, and forces no frame while
  /// [suppressForcedFrames] is set — so a caller that ends a suppressed episode
  /// must clear the flag before calling. The other order leaves a static screen
  /// unsampled, freezing the replay on the episode's last frame until the app
  /// happens to render again.
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
