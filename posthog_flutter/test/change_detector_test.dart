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

    testWidgets('resolves the interval once per start()', (tester) async {
      // The detector is stopped and restarted around every reconfigure, so the
      // cadence only has to follow a stop/start — not every tick.
      var interval = const Duration(seconds: 1);
      final detector = ChangeDetector(() {}, intervalOf: () => interval)
        ..hasCapturedPlatformViews = true;

      detector.start();
      await tester.pump();

      interval = const Duration(milliseconds: 250);
      await tester.binding.delayed(const Duration(milliseconds: 999));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'a running detector keeps the interval it started with');
      await tester.binding.delayed(const Duration(milliseconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();

      detector.stop();
      detector.start();
      await tester.pump();

      await tester.binding.delayed(const Duration(milliseconds: 249));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.binding.delayed(const Duration(milliseconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'the restart reads the new interval');

      detector.stop();
      await tester.pump();
    });

    testWidgets('does not start without an interval', (tester) async {
      // No interval means the SDK is not set up, so there is nothing to poll.
      var ticks = 0;
      final detector = ChangeDetector(() => ticks++, intervalOf: () => null)
        ..hasCapturedPlatformViews = true;

      detector.start();
      expect(detector.isRunning, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pump();
      await tester.binding.delayed(const Duration(seconds: 2));
      expect(ticks, 0);
    });

    testWidgets('forceNextTicks forces exactly the ticks it was given',
        (tester) async {
      // Without captured platform views nothing else forces a frame, so the
      // budget is the only thing keeping a static screen sampled.
      final detector =
          ChangeDetector(() {}, intervalOf: () => const Duration(seconds: 1));

      detector.start();
      await tester.pump();

      detector.forceNextTicks(2);
      for (var i = 0; i < 2; i++) {
        await tester.binding.delayed(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isTrue,
            reason: 'tick $i is still inside the budget');
        await tester.pump();
      }

      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'the budget is spent, so the detector stops paying for '
              'frames nothing asked for');

      detector.stop();
      await tester.pump();
    });

    testWidgets('cancelForcedTicks drops the rest of the budget',
        (tester) async {
      final detector =
          ChangeDetector(() {}, intervalOf: () => const Duration(seconds: 1));

      detector.start();
      await tester.pump();

      detector.forceNextTicks(3);
      detector.cancelForcedTicks();

      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'a delivered capture cancels the retries covering it');

      detector.stop();
      await tester.pump();
    });

    testWidgets('the forced-tick budget survives a stop()/start() pair',
        (tester) async {
      // Posthog.close() arms the budget while the detector is stopped, and the
      // setup() that follows is exactly what has to spend it: its own immediate
      // sample can be spent while the platform is briefly not recording.
      final detector =
          ChangeDetector(() {}, intervalOf: () => const Duration(seconds: 1));

      detector.start();
      await tester.pump();

      detector.stop();
      detector.forceNextTicks(2);
      detector.start();
      await tester.pump();

      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'clearing the budget on stop() would make the restarted '
              "recording depend on the statement order inside close()");

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
