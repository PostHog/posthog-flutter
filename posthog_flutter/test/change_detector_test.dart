import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/change_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChangeDetector forced frames', () {
    testWidgets('forces a frame for captured platform views', (tester) async {
      final detector =
          ChangeDetector(() {}, intervalOf: () => const Duration(seconds: 1));
      detector.hasCapturedPlatformViews = true;

      detector.start();
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'a static captured-view screen renders no frames on its '
              'own, so the detector must force them');

      detector.stop();
      await tester.pump();
    });

    testWidgets('does not force frames while suppressed', (tester) async {
      // During a native occlusion episode the Flutter capture is discarded,
      // so forcing the hidden tree to re-render every tick is pure cost.
      final detector =
          ChangeDetector(() {}, intervalOf: () => const Duration(seconds: 1));
      detector.hasCapturedPlatformViews = true;
      detector.suppressForcedFrames = true;

      detector.start();
      expect(tester.binding.hasScheduledFrame, isFalse);

      // Timer ticks while suppressed must not force frames either.
      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);

      detector.suppressForcedFrames = false;
      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'forced frames resume when the episode ends');

      detector.stop();
      await tester.pump();
    });

    testWidgets('forces only the first frame without captured platform views',
        (tester) async {
      final detector =
          ChangeDetector(() {}, intervalOf: () => const Duration(seconds: 1));

      detector.start();
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'the first sample is forced so a fully static screen still '
              'gets an initial capture after start()');

      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'later ticks must not force frames without captured '
              'platform views');

      detector.stop();
      await tester.pump();
    });

    testWidgets('re-arms each tick with the live interval', (tester) async {
      var interval = const Duration(seconds: 1);
      final detector = ChangeDetector(() {}, intervalOf: () => interval)
        ..hasCapturedPlatformViews = true;

      detector.start();
      await tester.pump();

      interval = const Duration(milliseconds: 250);
      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'a tick armed before the change still fires at the old '
              'interval');
      await tester.pump();

      await tester.binding.delayed(const Duration(milliseconds: 249));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.binding.delayed(const Duration(milliseconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'the next arm reads the new interval');

      detector.stop();
      await tester.pump();
    });

    testWidgets('keeps polling when intervalOf throws', (tester) async {
      // intervalOf reads the host app's config, so a broken one must fall back
      // to the last interval rather than propagate out of the timer callback,
      // which would leave _isRunning true with no timer pending: capture dead
      // for good, and an uncaught async error in the host app's zone.
      var resolves = 0;
      var ticks = 0;
      final detector = ChangeDetector(
        () => ticks++,
        intervalOf: () {
          resolves++;
          if (resolves == 2) {
            throw StateError('config blew up');
          }
          return const Duration(seconds: 1);
        },
      )..hasCapturedPlatformViews = true;

      detector.start();
      await tester.pump();
      expect(ticks, 1);

      for (var i = 0; i < 3; i++) {
        await tester.binding.delayed(const Duration(seconds: 1));
        await tester.pump();
      }

      expect(ticks, 4,
          reason: 'the failed resolve falls back to the last interval and the '
              'chain re-arms every tick');
      expect(detector.isRunning, isTrue);

      detector.stop();
      await tester.pump();
    });

    testWidgets('keeps polling when onChange throws', (tester) async {
      // A capture that blows up must not take the poll chain down with it:
      // every later frame would go unrecorded for the rest of the session.
      var ticks = 0;
      final detector = ChangeDetector(
        () {
          ticks++;
          throw StateError('capture blew up');
        },
        intervalOf: () => const Duration(seconds: 1),
      )..hasCapturedPlatformViews = true;

      detector.start();
      await tester.pump();
      expect(ticks, 1);
      expect(tester.takeException(), isStateError);

      for (var i = 0; i < 3; i++) {
        await tester.binding.delayed(const Duration(seconds: 1));
        await tester.pump();
        expect(tester.takeException(), isStateError);
      }

      expect(ticks, 4, reason: 'the chain keeps ticking through the failures');
      expect(detector.isRunning, isTrue);

      detector.stop();
      await tester.pump();
    });
  });
}
