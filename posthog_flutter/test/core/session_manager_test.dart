import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/session_manager.dart';

void main() {
  const minute = 60 * 1000;
  const hour = 60 * minute;

  group('PostHogSessionManager', () {
    test('starts a session when it is created', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final sessions = PostHogSessionManager();
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(sessions.id, isNotEmpty);
      expect(sessions.startedAt, inInclusiveRange(before, after));
    });

    test('keeps the session while events come within 30 minutes', () {
      final sessions = PostHogSessionManager();
      final start = sessions.startedAt;
      final id = sessions.id;

      expect(sessions.touch(start + 30 * minute), id);
      expect(sessions.touch(start + 60 * minute), id);
    });

    test('an event after 30 minutes without one starts a new session', () {
      final sessions = PostHogSessionManager();
      final start = sessions.startedAt;
      final id = sessions.touch(start);

      final next = sessions.touch(start + 30 * minute + 1);

      expect(next, isNot(id));
      expect(sessions.id, next);
      expect(sessions.startedAt, start + 30 * minute + 1);
    });

    test('a session ends 24 hours after it started, however active', () {
      final sessions = PostHogSessionManager();
      final start = sessions.startedAt;
      final id = sessions.id;

      for (var now = start; now <= start + 24 * hour; now += 20 * minute) {
        expect(sessions.touch(now), id);
      }

      expect(sessions.touch(start + 24 * hour + 1), isNot(id));
    });

    test('restart starts a new session at once', () {
      final sessions = PostHogSessionManager();
      final id = sessions.id;

      sessions.restart();

      expect(sessions.id, isNot(id));
    });
  });
}
