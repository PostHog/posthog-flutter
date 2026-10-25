import 'dart:async';

import 'package:meta/meta.dart';

import 'feature_flags_loaded.dart';
import 'posthog_flutter_platform_interface.dart';

/// Delivers each feature flags load to the listeners added with
/// [Posthog.onFeatureFlags].
@internal
class FeatureFlagsListeners {
  FeatureFlagsListeners._();

  static final instance = FeatureFlagsListeners._();

  final _listeners = <Object, OnFeatureFlagsCallback>{};
  PostHogFeatureFlagsLoaded? _last;

  PostHogFeatureFlagsSubscription add(OnFeatureFlagsCallback listener) {
    final token = Object();
    _listeners[token] = listener;
    final current = _last;
    if (current != null) {
      // Skipped if a newer load already reached the listener.
      scheduleMicrotask(() {
        if (_listeners.containsKey(token) && identical(_last, current)) {
          listener(current);
        }
      });
    }
    return PostHogFeatureFlagsSubscription(() => _listeners.remove(token));
  }

  void deliver(PostHogFeatureFlagsLoaded loaded) {
    _last = loaded;
    for (final entry in _listeners.entries.toList()) {
      // An earlier listener may have unsubscribed this one.
      if (_listeners.containsKey(entry.key)) entry.value(loaded);
    }
  }

  /// Forgets the last load, so new listeners don't get the previous user's
  /// flags after `reset()` or `close()`.
  void clear() => _last = null;
}
