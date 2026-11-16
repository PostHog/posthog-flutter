import 'uuid.dart';

/// The session that events are attributed to. A session ends after 30
/// minutes without events or 24 hours after it started, and the event that
/// follows starts a new one.
///
/// Times are wall-clock milliseconds since the epoch, so that a session also
/// ends while the device sleeps.
class PostHogSessionManager {
  /// Starts the first session.
  PostHogSessionManager() {
    restart();
  }

  static const _inactivityTimeout = Duration(minutes: 30);
  static const _maxLength = Duration(hours: 24);

  late String _id;
  late int _startedAt;
  late int _lastActiveAt;

  /// The id of the current session. Reading it neither extends nor ends the
  /// session.
  String get id => _id;

  /// When the current session started.
  int get startedAt => _startedAt;

  /// Ends the current session and starts a new one.
  void restart() => _startAt(DateTime.now().millisecondsSinceEpoch);

  /// Returns the session of an event at [now]: the current one, which the
  /// event keeps active, or a new one when the current one has ended.
  String touch(int now) {
    if (now - _lastActiveAt > _inactivityTimeout.inMilliseconds ||
        now - _startedAt > _maxLength.inMilliseconds) {
      _startAt(now);
    }
    _lastActiveAt = now;
    return _id;
  }

  void _startAt(int now) {
    _id = generateUuidV7();
    _startedAt = now;
    _lastActiveAt = now;
  }
}
