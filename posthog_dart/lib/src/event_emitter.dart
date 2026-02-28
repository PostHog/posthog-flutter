/// A simple event emitter supporting named events and wildcard listeners.
class SimpleEventEmitter {
  final Map<String, List<Function>> _events = {};

  /// Register a listener for an event. Returns an unsubscribe function.
  void Function() on(String event, Function listener) {
    _events.putIfAbsent(event, () => []);
    _events[event]!.add(listener);

    return () {
      _events[event]?.remove(listener);
    };
  }

  /// Emit an event with a payload.
  void emit(String event, [Object? payload]) {
    final listeners = _events[event];
    if (listeners != null) {
      for (final listener in List.of(listeners)) {
        listener(payload);
      }
    }

    // Wildcard listeners get both event name and payload
    final wildcardListeners = _events['*'];
    if (wildcardListeners != null) {
      for (final listener in List.of(wildcardListeners)) {
        listener(event, payload);
      }
    }
  }
}
