import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/change_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChangeDetector forced frames', () {
    testWidgets('forces a frame for captured platform views', (tester) async {
      final detector =
          ChangeDetector(() {}, interval: const Duration(seconds: 1));
      detector.hasCapturedPlatformViews = true;

      detector.start();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.binding.delayed(const Duration(seconds: 1));
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
          ChangeDetector(() {}, interval: const Duration(seconds: 1));
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
          ChangeDetector(() {}, interval: const Duration(seconds: 1));

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

    testWidgets('forceNextTicks forces exactly the ticks it was given',
        (tester) async {
      // Without captured platform views nothing else forces a frame, so the
      // budget is the only thing keeping a static screen sampled.
      final detector =
          ChangeDetector(() {}, interval: const Duration(seconds: 1));

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
          ChangeDetector(() {}, interval: const Duration(seconds: 1));

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
      final detector =
          ChangeDetector(() {}, interval: const Duration(seconds: 1));

      detector.start();
      await tester.pump();

      detector.forceNextTicks(2);
      detector.stop();
      detector.start();
      await tester.pump();

      for (var i = 0; i < 2; i++) {
        await tester.binding.delayed(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isTrue);
        await tester.pump();
      }
      await tester.binding.delayed(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);

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
        interval: const Duration(seconds: 1),
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

  group('ChangeDetector app lifecycle', () {
    const interval = Duration(seconds: 1);

    void setLifecycle(WidgetTester tester, AppLifecycleState state) {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      for (final step in _pathTo(state)) {
        tester.binding.handleAppLifecycleStateChanged(step);
      }
    }

    for (final away in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      testWidgets('schedules nothing while $away', (tester) async {
        var changes = 0;
        final detector = ChangeDetector(() => changes++, interval: interval)
          ..hasCapturedPlatformViews = true;

        detector.start();
        await tester.pump();
        expect(changes, 1);

        setLifecycle(tester, away);
        for (var i = 0; i < 3; i++) {
          await tester.binding.delayed(interval);
          expect(tester.binding.hasScheduledFrame, isFalse);
          await tester.pump();
        }
        expect(changes, 1);

        detector.stop();
        await tester.pump();
      });
    }

    testWidgets('samples once on return to resumed', (tester) async {
      var changes = 0;
      final detector = ChangeDetector(() => changes++, interval: interval);

      detector.start();
      await tester.pump();
      expect(changes, 1);

      setLifecycle(tester, AppLifecycleState.paused);
      await tester.binding.delayed(interval);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(changes, 2);

      await tester.pump();
      expect(changes, 2);

      detector.stop();
      await tester.pump();
    });

    testWidgets('a backgrounded tick does not spend the forced-tick budget', (
      tester,
    ) async {
      var changes = 0;
      final detector = ChangeDetector(() => changes++, interval: interval);

      detector.start();
      await tester.pump();

      detector.forceNextTicks(1);
      setLifecycle(tester, AppLifecycleState.inactive);
      for (var i = 0; i < 3; i++) {
        await tester.binding.delayed(interval);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final afterResume = changes;

      await tester.binding.delayed(interval);
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'the budget survived the backgrounded ticks',
      );
      await tester.pump();
      expect(changes, afterResume + 1);

      await tester.binding.delayed(interval);
      expect(tester.binding.hasScheduledFrame, isFalse);

      detector.stop();
      await tester.pump();
    });

    testWidgets('stop() removes the lifecycle observer', (tester) async {
      final detector = ChangeDetector(() {}, interval: interval);

      detector.start();
      await tester.pump();
      detector.stop();

      setLifecycle(tester, AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}

List<AppLifecycleState> _pathTo(AppLifecycleState target) => switch (target) {
      AppLifecycleState.inactive => [AppLifecycleState.inactive],
      AppLifecycleState.hidden => [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
        ],
      AppLifecycleState.paused => [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ],
      AppLifecycleState.resumed => [AppLifecycleState.resumed],
      AppLifecycleState.detached => [AppLifecycleState.detached],
    };
