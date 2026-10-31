import 'dart:async';

import 'package:meta/meta.dart';

import 'feature_flags_loaded.dart';
import 'posthog_flutter_platform_interface.dart';
import 'util/logging.dart';

/// Delivers each feature flags load to the listeners added with
/// [Posthog.onFeatureFlags].
@internal
class FeatureFlagsListeners {
  FeatureFlagsListeners._();

  static final instance = FeatureFlagsListeners._();

  final _listeners = <Object, OnFeatureFlagsCallback>{};
  PostHogFeatureFlagsLoaded? _last;
  int _generation = 0;

  /// Bumped by [clear]. The native SDKs tag each load with the generation
  /// they last got, so a load sent before a `reset()` or `close()` reached
  /// them can be told apart.
  int get generation => _generation;

  PostHogFeatureFlagsSubscription add(OnFeatureFlagsCallback listener) {
    final token = Object();
    _listeners[token] = listener;
    final current = _last;
    if (current != null) {
      // Skipped if a newer load already reached the listener.
      scheduleMicrotask(() {
        if (_listeners.containsKey(token) && identical(_last, current)) {
          _notify(listener, current);
        }
      });
    }
    return PostHogFeatureFlagsSubscription(() => _listeners.remove(token));
  }

  void deliver(PostHogFeatureFlagsLoaded loaded) {
    _last = loaded;
    for (final entry in _listeners.entries.toList()) {
      // An earlier listener may have unsubscribed this one.
      if (_listeners.containsKey(entry.key)) _notify(entry.value, loaded);
    }
  }

  // A throwing listener must not stop the others from getting the load.
  void _notify(
      OnFeatureFlagsCallback listener, PostHogFeatureFlagsLoaded loaded) {
    try {
      listener(loaded);
    } catch (e) {
      printIfDebug('onFeatureFlags listener threw: $e');
    }
  }

  /// Forgets the last load, so new listeners don't get the previous user's
  /// flags after `reset()` or `close()`.
  void clear() {
    _last = null;
    _generation++;
  }
}
