import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// A class that detects changes in the UI and executes a callback when changes occur.
///
/// The `ChangeDetector` continuously monitors the Flutter widget tree by scheduling
/// a callback after each frame is rendered. This is useful when you need to perform
/// an action whenever the UI updates.
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
/// **Note:** Since the `onChange` callback is called after every frame, ensure that
/// the operations performed are efficient to avoid impacting app performance.
class ChangeDetector {
  final VoidCallback onChange;
  bool _isRunning = false;

  /// Creates a [ChangeDetector] with the given [onChange] callback.
  ChangeDetector(this.onChange);

  /// Starts the change detection process.
  ///
  /// This method schedules the [_onFrameRendered] callback to be called
  /// after each frame is rendered.
  void start() {
    if (!_isRunning) {
      _isRunning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onFrameRendered();
      });
    }
  }

  /// Stops the change detection process.
  ///
  /// This prevents the [onChange] callback from being called after each frame.
  void stop() {
    _isRunning = false;
  }

  /// Internal method called after each frame is rendered.
  ///
  /// Executes the [onChange] callback and schedules itself for the next frame
  /// if the change detector is still running.
  void _onFrameRendered() {
    final config = Posthog().config;
    if (config == null || !config.sessionReplay) {
      return;
    }

    if (!_isRunning) {
      return;
    }

    onChange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onFrameRendered();
    });
  }
}
