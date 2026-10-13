/// A simple event emitter supporting named events and catch-all listeners.
class SimpleEventEmitter {
  final Map<String, List<void Function(Object?)>> _listeners = {};
  final List<void Function(String, Object?)> _anyListeners = [];
  final void Function(Object error) _onListenerError;

  SimpleEventEmitter({required void Function(Object error) onListenerError})
      : _onListenerError = onListenerError;

  /// Registers a listener for [event]. Returns an unsubscribe function.
  void Function() on(String event, void Function(Object? payload) listener) {
    final listeners = _listeners.putIfAbsent(event, () => []);
    listeners.add(listener);

    return () {
      listeners.remove(listener);
    };
  }

  /// Registers a listener for every event. Returns an unsubscribe function.
  void Function() onAny(void Function(String event, Object? payload) listener) {
    _anyListeners.add(listener);

    return () {
      _anyListeners.remove(listener);
    };
  }

  /// Emits an event with a payload. A listener that throws is reported via
  /// the error hook and does not stop the other listeners.
  void emit(String event, Object? payload) {
    final listeners = _listeners[event];
    if (listeners != null) {
      for (final listener in List.of(listeners)) {
        _guard(() => listener(payload));
      }
    }

    for (final listener in List.of(_anyListeners)) {
      _guard(() => listener(event, payload));
    }
  }

  void _guard(void Function() invoke) {
    try {
      invoke();
    } catch (e) {
      _onListenerError(e);
    }
  }
}
