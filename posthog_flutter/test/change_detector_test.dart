import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/change_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChangeDetector forced frames', () {
    testWidgets('forces a frame for captured platform views', (tester) async {
      final detector = ChangeDetector(() {});
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
      final detector = ChangeDetector(() {});
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

    testWidgets('does not force frames without captured platform views',
        (tester) async {
      final detector = ChangeDetector(() {});

      detector.start();
      expect(tester.binding.hasScheduledFrame, isFalse);

      detector.stop();
      await tester.pump();
    });
  });
}
