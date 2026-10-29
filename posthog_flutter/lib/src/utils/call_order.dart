import 'dart:async';

import '../util/logging.dart';

/// Hands calls to the underlying SDK in the order the app made them.
///
/// The native SDKs and posthog-js run beforeSend synchronously inside
/// capture, so an event always goes out with the user, super properties,
/// groups and consent it was captured under. Flutter's beforeSend can be
/// async. While one runs, later calls such as reset() or identify() wait here
/// until the event has been handed over, so they still apply after it.
class CallOrder {
  /// A beforeSend that runs longer than this stops holding back later calls.
  /// Its event is still sent when the callbacks finish.
  static const maxWait = Duration(seconds: 10);

  // Set while a turn is being used: calls made from beforeSend, or from the
  // call that hands an event over, must not wait for the turn they run in.
  static final Object _inTurn = Object();

  Future<void>? _last;

  /// Runs [call] now when nothing is waiting, otherwise after every earlier
  /// call has been handed over. [call] must hand over before its first await.
  Future<T> run<T>(Future<T> Function() call) {
    if (_last == null || _isInTurn) return call();
    final turn = _take();
    return turn.ahead.then((_) {
      try {
        return _inZone(call);
      } finally {
        turn.end();
      }
    });
  }

  /// Runs [hook] once every earlier call has been handed over, so it sees
  /// the state the app left before capturing, then hands its result to
  /// [send]. Later calls wait for [send] to finish, so it may itself capture
  /// (a beforeSend that renames a `$screen` does).
  Future<void> event<E>(
    FutureOr<E> Function() hook,
    Future<void> Function(E event) send,
  ) async {
    if (_isInTurn) {
      final hooked = hook();
      return send(hooked is Future<E> ? await hooked : hooked);
    }
    if (_last == null) {
      final hooked = _inZone(hook);
      if (hooked is! Future<E>) return send(hooked);
      return _hold(_take(), () => hooked, send);
    }
    final turn = _take();
    await turn.ahead;
    return _hold(turn, () => _inZone(hook), send);
  }

  Future<void> _hold<E>(
    _Turn turn,
    FutureOr<E> Function() hook,
    Future<void> Function(E event) send,
  ) async {
    final timer = Timer(maxWait, () {
      printIfDebug('[PostHog] beforeSend took longer than '
          '${maxWait.inSeconds}s; later calls no longer wait for it.');
      turn.end();
    });
    try {
      final hooked = hook();
      final processed = hooked is Future<E> ? await hooked : hooked;
      await _inZone(() => send(processed));
    } finally {
      timer.cancel();
      turn.end();
    }
  }

  bool get _isInTurn => Zone.current[_inTurn] == true;

  R _inZone<R>(R Function() body) =>
      runZoned(body, zoneValues: {_inTurn: true});

  _Turn _take() {
    final ahead = _last ?? Future<void>.value();
    final done = Completer<void>();
    final mine = done.future;
    _last = mine;
    return _Turn(ahead, () {
      if (done.isCompleted) return;
      if (identical(_last, mine)) _last = null;
      done.complete();
    });
  }
}

class _Turn {
  _Turn(this.ahead, this.end);

  final Future<void> ahead;
  final void Function() end;
}
