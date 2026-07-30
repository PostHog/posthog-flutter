import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    // false so the ChangeDetector's periodic captures self-drop
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isSessionReplayActive') {
        return false;
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

  testWidgets(
      'a close()/setup() reconfigure rebuilds the capture components '
      'against the new config', (tester) async {
    final first = replayConfig(const Duration(milliseconds: 500));
    await Posthog().setup(first);

    await tester.pumpWidget(const PostHogWidget(child: SizedBox.shrink()));
    // extra pumps drain the zero-duration capture future the first frame
    // callback kicks off (the mocked isSessionReplayActive drops it)
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    final state = tester.state<PostHogWidgetState>(find.byType(PostHogWidget));

    expect(
        state.debugChangeDetector?.interval, const Duration(milliseconds: 500));
    expect(state.debugScreenshotCapturer?.effectiveConfig, same(first));

    await Posthog().close();
    final second = replayConfig(const Duration(milliseconds: 250));
    await Posthog().setup(second);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(
        state.debugChangeDetector?.interval, const Duration(milliseconds: 250));
    expect(state.debugChangeDetector?.isRunning, isTrue);
    expect(state.debugScreenshotCapturer?.effectiveConfig, same(second));

    // stops the detector's periodic timer before the test framework's
    // pending-timer check, then drains the last capture future
    await Posthog().close();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    // With the live config nulled by close(), effectiveConfig only returns
    // `second` from a rebuilt capturer's constructor config — pre-close the
    // live-config fallback would mask a capturer that was never rebuilt.
    expect(state.debugScreenshotCapturer?.effectiveConfig, same(second));
  });

  testWidgets(
      'a close()/setup() reconfigure keeps forcing frames when platform '
      'views were captured', (tester) async {
    final first = replayConfig(const Duration(milliseconds: 500));
    await Posthog().setup(first);

    await tester.pumpWidget(const PostHogWidget(child: SizedBox.shrink()));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    final state = tester.state<PostHogWidgetState>(find.byType(PostHogWidget));

    state.debugScreenshotCapturer?.hasCapturedPlatformViews = true;
    state.debugChangeDetector?.hasCapturedPlatformViews = true;

    await Posthog().close();
    final second = replayConfig(const Duration(milliseconds: 250));
    await Posthog().setup(second);

    // On a static screen with revealed platform views, only the forced frame
    // this flag gates ever re-runs a capture — so the rebuilt detector must
    // inherit it or capture stalls until the Flutter tree next repaints.
    expect(state.debugChangeDetector?.hasCapturedPlatformViews, isTrue);

    // A bailed capture attempt refreshes the detector from the capturer, so
    // the carry must survive it — a fresh-false capturer would erase it here.
    state.debugChangeDetector?.onChange();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(state.debugChangeDetector?.hasCapturedPlatformViews, isTrue);

    await Posthog().close();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  });

  testWidgets(
      'a close()/setup() reconfigure reusing the same config instance with '
      'throttleDelay mutated in place rebuilds the detector', (tester) async {
    final config = replayConfig(const Duration(milliseconds: 500));
    await Posthog().setup(config);

    await tester.pumpWidget(const PostHogWidget(child: SizedBox.shrink()));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    final state = tester.state<PostHogWidgetState>(find.byType(PostHogWidget));

    expect(
        state.debugChangeDetector?.interval, const Duration(milliseconds: 500));

    await Posthog().close();
    config.sessionReplayConfig.throttleDelay =
        const Duration(milliseconds: 250);
    await Posthog().setup(config);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);

    expect(
        state.debugChangeDetector?.interval, const Duration(milliseconds: 250));
    expect(state.debugChangeDetector?.isRunning, isTrue);

    await Posthog().close();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  });

  testWidgets('recording restarts with the same config keep the components',
      (tester) async {
    final config = replayConfig(const Duration(milliseconds: 500));
    await Posthog().setup(config);

    await tester.pumpWidget(const PostHogWidget(child: SizedBox.shrink()));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    final state = tester.state<PostHogWidgetState>(find.byType(PostHogWidget));
    final detector = state.debugChangeDetector;

    PostHogInternalEvents.sessionRecordingActive.value = false;
    PostHogInternalEvents.sessionRecordingActive.value = true;

    expect(state.debugChangeDetector, same(detector));
    expect(state.debugChangeDetector?.isRunning, isTrue);

    await Posthog().close();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  });
}
