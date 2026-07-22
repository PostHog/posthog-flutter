import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final recordedCalls = <MethodCall>[];
  var enableNativeBridgeResult = false;
  // Optional side effect run inside the sendMetaEvent handler, used to
  // simulate the world changing mid-send (between meta and full snapshot).
  void Function()? onSendMetaEvent;

  void mockChannel() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      switch (call.method) {
        // false so the ChangeDetector's periodic captures self-drop before
        // sending anything: these tests drive the occlusion paths only.
        case 'isSessionReplayActive':
          return false;
        case 'enableNativeBridge':
          return enableNativeBridgeResult;
        case 'sendMetaEvent':
          onSendMetaEvent?.call();
          return null;
        default:
          return null;
      }
    });
  }

  /// Mirrors what posthog_flutter_io does on an onNativeOcclusionChanged push.
  void pushOcclusion({
    required bool occluded,
    required int episode,
    bool bridgeFailed = false,
  }) {
    PostHogInternalEvents.nativeOcclusionActive = occluded;
    PostHogInternalEvents.nativeOcclusionEpisode = episode;
    PostHogInternalEvents.nativeBridgeFailed = bridgeFailed;
    PostHogInternalEvents.nativeOcclusionEvent.value++;
  }

  void resetOcclusionState() {
    PostHogInternalEvents.nativeOcclusionActive = false;
    PostHogInternalEvents.nativeOcclusionEpisode = 0;
    PostHogInternalEvents.nativeBridgeFailed = false;
  }

  Future<void> setupPosthog(PostHogConfig config) async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    await Posthog().setup(config);
  }

  PostHogConfig replayConfig({required bool captureNativeScreens}) {
    final config = PostHogConfig('test_project_token');
    config.sessionReplay = true;
    config.sessionReplayConfig.captureNativeScreens = captureNativeScreens;
    return config;
  }

  Future<PostHogWidgetState> pumpReplayWidget(WidgetTester tester) async {
    await tester.pumpWidget(
      PostHogWidget(child: Container(color: const Color(0xFF00FF00))),
    );
    return tester.state<PostHogWidgetState>(find.byType(PostHogWidget));
  }

  /// Unmounts the replay widget (stopping its change detector) and flushes
  /// any in-flight zero-duration capture timers so none are pending at
  /// test teardown. The pumps need an explicit duration: without one the
  /// fake clock never elapses and due timers stay pending.
  Future<void> unmountAndFlush(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Lets the occlusion handler's real-async work (placeholder rasterization,
  /// channel round-trips) run to completion.
  Future<void> settleRealAsync(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  setUp(() {
    recordedCalls.clear();
    enableNativeBridgeResult = false;
    onSendMetaEvent = null;
    resetOcclusionState();
    mockChannel();
  });

  tearDown(() async {
    resetOcclusionState();
    await Posthog().close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('captureNativeScreens runtime toggle', () {
    test('propagates only from the active config, only on real changes',
        () async {
      final fake = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fake;
      final config = replayConfig(captureNativeScreens: true);

      // Before setup the value crosses inside the config map instead.
      config.sessionReplayConfig.captureNativeScreens = false;
      expect(fake.captureNativeScreensChanges, isEmpty);

      await Posthog().setup(config);
      config.sessionReplayConfig.captureNativeScreens = true;
      config.sessionReplayConfig.captureNativeScreens = true;
      config.sessionReplayConfig.captureNativeScreens = false;
      expect(fake.captureNativeScreensChanges, [true, false],
          reason: 'each real change crosses once; the no-op set does not');

      final inactive = PostHogConfig('other_token');
      inactive.sessionReplayConfig.captureNativeScreens = true;
      expect(fake.captureNativeScreensChanges, [true, false],
          reason: 'a config that is not the active one must not propagate');
    });

    test('a second setup hands propagation to the new config', () async {
      final fake = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fake;
      final first = replayConfig(captureNativeScreens: true);
      await Posthog().setup(first);

      final second = replayConfig(captureNativeScreens: false);
      await Posthog().setup(second);

      first.sessionReplayConfig.captureNativeScreens = false;
      expect(fake.captureNativeScreensChanges, isEmpty,
          reason: 'the replaced config must stop propagating');

      second.sessionReplayConfig.captureNativeScreens = true;
      expect(fake.captureNativeScreensChanges, [true],
          reason: 'the active config propagates');
    });
  });

  group('episodeStillCurrent', () {
    test('true only while both the episode id and occlusion state match', () {
      PostHogInternalEvents.nativeOcclusionEpisode = 3;
      PostHogInternalEvents.nativeOcclusionActive = true;

      expect(
          PostHogInternalEvents.episodeStillCurrent(3, occluded: true), isTrue);
      expect(
        PostHogInternalEvents.episodeStillCurrent(3, occluded: false),
        isFalse,
        reason: 'occlusion state flipped',
      );
      expect(
        PostHogInternalEvents.episodeStillCurrent(2, occluded: true),
        isFalse,
        reason: 'a new episode started while the operation was in flight',
      );

      PostHogInternalEvents.nativeOcclusionActive = false;
      expect(
        PostHogInternalEvents.episodeStillCurrent(3, occluded: true),
        isFalse,
        reason: 'episode ended',
      );
      expect(
        PostHogInternalEvents.episodeStillCurrent(3, occluded: false),
        isTrue,
      );
    });
  });

  group('occlusion episode handling', () {
    testWidgets('placeholder ships as a meta + full snapshot pair',
        (tester) async {
      await setupPosthog(replayConfig(captureNativeScreens: true));
      await pumpReplayWidget(tester);
      recordedCalls.clear();

      pushOcclusion(occluded: true, episode: 1);
      await settleRealAsync(tester);

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendMetaEvent'));
      expect(methods, contains('sendFullSnapshot'));
      expect(
        methods.indexOf('sendMetaEvent'),
        lessThan(methods.indexOf('sendFullSnapshot')),
        reason: 'meta must precede the frame it describes',
      );

      await unmountAndFlush(tester);
    });

    testWidgets('no full snapshot when the episode ends during the meta await',
        (tester) async {
      // The stale-frame-leak regression: a send passes the entry validity
      // check, then the world changes while sendMetaEvent is in flight. The
      // full snapshot must not ship into the changed world — a bare meta is
      // acceptable (it self-corrects), a mispaired full is not.
      await setupPosthog(replayConfig(captureNativeScreens: true));
      await pumpReplayWidget(tester);
      recordedCalls.clear();

      onSendMetaEvent = () => pushOcclusion(occluded: false, episode: 1);

      pushOcclusion(occluded: true, episode: 1);
      await settleRealAsync(tester);

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendMetaEvent'));
      expect(methods, isNot(contains('sendFullSnapshot')),
          reason: 'validity re-checked after the meta await drops the frame');

      await unmountAndFlush(tester);
    });

    testWidgets('frame is dropped when a new episode starts during the send',
        (tester) async {
      // The generation-counter case: episode 1 ends AND episode 2 begins
      // while episode 1's placeholder is mid-send, so the occlusion boolean
      // is back to true and only the episode id reveals the world changed. A
      // boolean-only validity check would ship episode 1's stale frame into
      // episode 2's stream — the regression that reopened this bug family
      // three times.
      await setupPosthog(replayConfig(captureNativeScreens: true));
      await pumpReplayWidget(tester);
      recordedCalls.clear();

      var flipped = false;
      onSendMetaEvent = () {
        if (flipped) return;
        flipped = true;
        pushOcclusion(occluded: false, episode: 1);
        pushOcclusion(occluded: true, episode: 2);
      };

      pushOcclusion(occluded: true, episode: 1);
      // Two settles: episode 2's own placeholder build+send starts only after
      // episode 1's send unwinds.
      await settleRealAsync(tester);
      await settleRealAsync(tester);

      final fulls =
          recordedCalls.where((c) => c.method == 'sendFullSnapshot').length;
      expect(fulls, 1,
          reason: "only episode 2's own placeholder may send; episode 1's "
              'stale frame must be dropped by the episode-id check');

      await unmountAndFlush(tester);
    });

    testWidgets('placeholder is dropped when its episode ends mid-build',
        (tester) async {
      await setupPosthog(replayConfig(captureNativeScreens: true));
      await pumpReplayWidget(tester);
      recordedCalls.clear();

      // The start handler runs synchronously up to the placeholder's first
      // await; ending the episode here makes the world it captured stale.
      pushOcclusion(occluded: true, episode: 1);
      pushOcclusion(occluded: false, episode: 1);
      await settleRealAsync(tester);

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, isNot(contains('sendFullSnapshot')));
      expect(methods, isNot(contains('sendMetaEvent')));

      await unmountAndFlush(tester);
    });

    testWidgets('ignores occlusion when the bridge is off', (tester) async {
      await setupPosthog(replayConfig(captureNativeScreens: false));
      final state = await pumpReplayWidget(tester);

      pushOcclusion(occluded: true, episode: 1);
      await tester.pump();

      expect(
        state.debugFlutterCaptureSuppressed,
        isFalse,
        reason: 'bridge off means pre-bridge behavior: keep recording',
      );

      await unmountAndFlush(tester);
    });

    testWidgets('suppresses Flutter capture while the placeholder owns it',
        (tester) async {
      await setupPosthog(replayConfig(captureNativeScreens: true));
      final state = await pumpReplayWidget(tester);

      pushOcclusion(occluded: true, episode: 1);
      await settleRealAsync(tester);
      expect(state.debugFlutterCaptureSuppressed, isTrue);

      pushOcclusion(occluded: false, episode: 1);
      await tester.pump();
      expect(state.debugFlutterCaptureSuppressed, isFalse);

      await unmountAndFlush(tester);
    });

    testWidgets('episode end schedules a frame so a static screen resumes',
        (tester) async {
      // A static screen renders no frame after the cover dismisses, and
      // addPostFrameCallback alone does not request one — without an explicit
      // scheduleFrame the replay would stay on the episode's last frame.
      await setupPosthog(replayConfig(captureNativeScreens: true));
      await pumpReplayWidget(tester);

      pushOcclusion(occluded: true, episode: 1);
      await settleRealAsync(tester);

      pushOcclusion(occluded: false, episode: 1);
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'episode end must force a frame to re-arm capture');

      await unmountAndFlush(tester);
    });

    testWidgets('bridge handshake carries the episode id', (tester) async {
      enableNativeBridgeResult = true;
      await setupPosthog(replayConfig(captureNativeScreens: true));
      await pumpReplayWidget(tester);
      recordedCalls.clear();

      pushOcclusion(occluded: true, episode: 7);
      await settleRealAsync(tester);

      final enable = recordedCalls.firstWhere(
        (c) => c.method == 'enableNativeBridge',
      );
      expect(enable.arguments, {'episode': 7},
          reason: 'the native side declines a stale enable by episode id');
      expect(
        recordedCalls.map((c) => c.method),
        isNot(anyOf(contains('sendMetaEvent'), contains('sendFullSnapshot'))),
        reason:
            'an accepted bridge owns the episode: Dart must not also ship a '
            'placeholder or snapshot for it (no double frame)',
      );

      await unmountAndFlush(tester);
    });

    testWidgets('bridge-failed re-push falls back to the placeholder',
        (tester) async {
      enableNativeBridgeResult = true;
      await setupPosthog(replayConfig(captureNativeScreens: true));
      final state = await pumpReplayWidget(tester);

      pushOcclusion(occluded: true, episode: 1);
      await settleRealAsync(tester);
      expect(state.debugFlutterCaptureSuppressed, isTrue,
          reason: 'bridge accepted, native capture owns the episode');
      recordedCalls.clear();

      // Native discovered it cannot deliver and re-pushed with bridgeFailed.
      pushOcclusion(occluded: true, episode: 1, bridgeFailed: true);
      await settleRealAsync(tester);
      expect(state.debugFlutterCaptureSuppressed, isTrue,
          reason: 'the placeholder owns the episode now');
      expect(recordedCalls.map((c) => c.method), contains('sendFullSnapshot'));

      await unmountAndFlush(tester);
    });

    // A native→native cover swap inside the end-debounce window arrives as a
    // new occluded=true episode with no occluded=false between.
    testWidgets('cover swap with the flag now off releases the bridge grant',
        (tester) async {
      enableNativeBridgeResult = true;
      final config = replayConfig(captureNativeScreens: true);
      await setupPosthog(config);
      final state = await pumpReplayWidget(tester);

      pushOcclusion(occluded: true, episode: 1);
      await settleRealAsync(tester);
      expect(state.debugFlutterCaptureSuppressed, isTrue,
          reason: 'episode 1 was granted while the flag was on');

      config.sessionReplayConfig.captureNativeScreens = false;
      recordedCalls.clear();
      pushOcclusion(occluded: true, episode: 2);
      await settleRealAsync(tester);

      expect(state.debugFlutterCaptureSuppressed, isFalse,
          reason: 'flag off: Flutter keeps recording the covered tree');
      expect(
        recordedCalls.map((c) => c.method),
        isNot(contains('enableNativeBridge')),
        reason: 'no grant may be negotiated for the swapped cover',
      );
      expect(
        recordedCalls.map((c) => c.method),
        isNot(contains('sendFullSnapshot')),
        reason: 'flag off also means no placeholder',
      );

      await unmountAndFlush(tester);
    });

    testWidgets('cover swap with the flag still on re-negotiates seamlessly',
        (tester) async {
      enableNativeBridgeResult = true;
      await setupPosthog(replayConfig(captureNativeScreens: true));
      final state = await pumpReplayWidget(tester);

      pushOcclusion(occluded: true, episode: 1);
      await settleRealAsync(tester);
      recordedCalls.clear();

      pushOcclusion(occluded: true, episode: 2);
      await settleRealAsync(tester);

      final enable = recordedCalls.firstWhere(
        (c) => c.method == 'enableNativeBridge',
      );
      expect(enable.arguments, {'episode': 2},
          reason: 'the swapped cover gets its own grant');
      expect(state.debugFlutterCaptureSuppressed, isTrue,
          reason: 'no end event between episodes: suppression never lapses');
      expect(
        recordedCalls.map((c) => c.method),
        isNot(anyOf(contains('sendMetaEvent'), contains('sendFullSnapshot'))),
        reason: 'the re-granted bridge owns the frame, no placeholder',
      );

      await unmountAndFlush(tester);
    });
  });

  group('confirmDelivered', () {
    testWidgets('commits the status captured with the frame', (tester) async {
      final config = replayConfig(captureNativeScreens: true);
      await setupPosthog(config);
      await pumpReplayWidget(tester);

      final capturer = ScreenshotCapturer(config);
      final imageInfo = await tester.runAsync(
        () => capturer.buildOcclusionPlaceholder(),
      );
      expect(imageInfo, isNotNull);
      final status = capturer.debugLastTargetStatus;
      expect(status, isNotNull);
      expect(status!.sentMetaEvent, isFalse);

      capturer.confirmDelivered(imageInfo!.id + 1, metaSent: true);
      expect(status.sentMetaEvent, isFalse,
          reason: 'a mismatched id means a recreated view: no commit');

      capturer.confirmDelivered(imageInfo.id, metaSent: true);
      expect(status.sentMetaEvent, isTrue);

      await unmountAndFlush(tester);
    });

    testWidgets('does not latch meta when metaSent is false', (tester) async {
      final config = replayConfig(captureNativeScreens: true);
      await setupPosthog(config);
      await pumpReplayWidget(tester);

      final capturer = ScreenshotCapturer(config);
      final imageInfo = await tester.runAsync(
        () => capturer.buildOcclusionPlaceholder(),
      );
      final status = capturer.debugLastTargetStatus!;

      capturer.confirmDelivered(imageInfo!.id, metaSent: false);
      expect(status.sentMetaEvent, isFalse);

      await unmountAndFlush(tester);
    });

    testWidgets('placeholder always carries meta, even when latched',
        (tester) async {
      final config = replayConfig(captureNativeScreens: true);
      await setupPosthog(config);
      await pumpReplayWidget(tester);

      final capturer = ScreenshotCapturer(config);
      final first = await tester.runAsync(
        () => capturer.buildOcclusionPlaceholder(),
      );
      capturer.confirmDelivered(first!.id, metaSent: true);

      final second = await tester.runAsync(
        () => capturer.buildOcclusionPlaceholder(),
      );
      expect(second!.shouldSendMetaEvent, isTrue,
          reason: 'a bridged episode may have shipped the native screen meta '
              'in between; the placeholder must restate the Flutter viewport');

      await unmountAndFlush(tester);
    });

    testWidgets('onOcclusionEnded re-arms via the held status reference',
        (tester) async {
      final config = replayConfig(captureNativeScreens: true);
      await setupPosthog(config);
      await pumpReplayWidget(tester);

      final capturer = ScreenshotCapturer(config);
      final imageInfo = await tester.runAsync(
        () => capturer.buildOcclusionPlaceholder(),
      );
      final status = capturer.debugLastTargetStatus!;
      capturer.confirmDelivered(imageInfo!.id, metaSent: true);
      status.imageBytesHash = 12345;
      status.compositedBytesHash = 67890;
      expect(status.sentMetaEvent, isTrue);

      capturer.onOcclusionEnded();

      expect(status.sentMetaEvent, isFalse,
          reason: 'the recovery path must re-arm meta for the next frame');
      expect(status.imageBytesHash, isNull);
      expect(status.compositedBytesHash, isNull,
          reason: 'dedup hashes cleared so the first post-occlusion frame '
              'is never deduped away');

      await unmountAndFlush(tester);
    });
  });
}
