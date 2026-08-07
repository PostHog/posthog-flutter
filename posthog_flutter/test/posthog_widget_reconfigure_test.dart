import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'posthog_flutter_platform_interface_fake.dart';

/// Stands in for an app that keeps rendering (an animation, a spinner). The
/// detector samples from a post-frame callback, so without rendered frames a
/// poll tick produces no capture at all and the cadence is unobservable.
class _AlwaysRepainting extends StatefulWidget {
  const _AlwaysRepainting();

  @override
  State<_AlwaysRepainting> createState() => _AlwaysRepaintingState();
}

class _AlwaysRepaintingState extends State<_AlwaysRepainting> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    return const SizedBox.shrink();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  var captureAttempts = 0;

  setUp(() async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    captureAttempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSessionReplayState') {
        captureAttempts++;
        // inactive so the capture self-drops before rasterizing; the call
        // itself is the observable evidence that a poll tick reached capture.
        return {'isActive': false};
      }
      return null;
    });
    await Posthog().close();
  });

  tearDown(() async {
    await Posthog().close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  PostHogConfig replayConfig(Duration throttleDelay) {
    return PostHogConfig('test_project_token')
      ..sessionReplay = true
      ..sessionReplayConfig.throttleDelay = throttleDelay;
  }

  /// Renders frames for [window] and returns how many captures were attempted.
  /// Each pump renders the frame that the previous poll tick's post-frame
  /// callback is waiting on, so the count is the number of ticks in [window].
  Future<int> captureAttemptsOver(WidgetTester tester, Duration window) async {
    captureAttempts = 0;
    const step = Duration(milliseconds: 25);
    for (var elapsed = Duration.zero; elapsed < window; elapsed += step) {
      await tester.pump(step);
    }
    // drains the last tick's capture future without advancing the clock
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    return captureAttempts;
  }

  testWidgets('a close()/setup() reconfigure changes the capture rate',
      (tester) async {
    await Posthog().setup(replayConfig(const Duration(milliseconds: 500)));

    await tester.pumpWidget(const PostHogWidget(child: _AlwaysRepainting()));
    // extra pumps drain the zero-duration capture future the first frame
    // callback kicks off (the mocked inactive state drops it)
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(await captureAttemptsOver(tester, const Duration(seconds: 1)), 2);

    await Posthog().close();
    await Posthog().setup(replayConfig(const Duration(milliseconds: 250)));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(await captureAttemptsOver(tester, const Duration(seconds: 1)), 4,
        reason: 'the new throttleDelay must drive the real capture rate');

    // stops the detector's periodic timer before the test framework's
    // pending-timer check, then drains the last capture future
    await Posthog().close();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  });

  testWidgets(
      'a close()/setup() reconfigure reusing the same config instance with '
      'throttleDelay mutated in place changes the capture rate',
      (tester) async {
    final config = replayConfig(const Duration(milliseconds: 500));
    await Posthog().setup(config);

    await tester.pumpWidget(const PostHogWidget(child: _AlwaysRepainting()));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(await captureAttemptsOver(tester, const Duration(seconds: 1)), 2);

    await Posthog().close();
    config.sessionReplayConfig.throttleDelay =
        const Duration(milliseconds: 250);
    await Posthog().setup(config);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(await captureAttemptsOver(tester, const Duration(seconds: 1)), 4,
        reason: 'a config identical by identity still has to be re-read');

    await Posthog().close();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  });
}
