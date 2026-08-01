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
  var sessionReplayActive = false;
  // The session id the native SDK would report. Rotating it stands in for
  // every rotation Dart cannot predict (reset(), idle/max-duration expiry).
  String? sessionId = 'session-a';
  // Optional side effect run inside the sendMetaEvent handler, used to
  // simulate the world changing mid-send (between meta and full snapshot).
  void Function()? onSendMetaEvent;

  void mockChannel() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      switch (call.method) {
        // Defaults to inactive so the ChangeDetector's periodic captures
        // self-drop before sending anything: most tests here drive the
        // occlusion paths only.
        case 'getSessionReplayState':
          return {'isActive': sessionReplayActive, 'sessionId': sessionId};
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

  /// Drives a full periodic capture to completion: it interleaves fake-async
  /// work (channel round-trips, the detector's timer) with real async
  /// (rasterization), so neither pumping nor [runAsync] alone gets there.
  Future<void> settleCapture(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
  }

  setUp(() {
    recordedCalls.clear();
    enableNativeBridgeResult = false;
    sessionReplayActive = false;
    sessionId = 'session-a';
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

    test('a close()/setup() reconfigure hands propagation to the new config',
        () async {
      final fake = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fake;
      final first = replayConfig(captureNativeScreens: true);
      await Posthog().setup(first);

      final second = replayConfig(captureNativeScreens: false);
      await Posthog().setup(second);
      second.sessionReplayConfig.captureNativeScreens = true;
      expect(fake.captureNativeScreensChanges, isEmpty,
          reason: 'a setup without close is ignored, so its config '
              'must not propagate');

      await Posthog().close();
      await Posthog().setup(second);

      first.sessionReplayConfig.captureNativeScreens = false;
      expect(fake.captureNativeScreensChanges, isEmpty,
          reason: 'the replaced config must stop propagating');

      second.sessionReplayConfig.captureNativeScreens = false;
      expect(fake.captureNativeScreensChanges, [false],
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

  group('capture gate', () {
    // Counterpart to posthog_widget_web_test.dart: the kIsWeb guard must not
    // disable capture off web.
    testWidgets('reaches captureScreenshot while session replay is on',
        (tester) async {
      await setupPosthog(replayConfig(captureNativeScreens: false));
      await pumpReplayWidget(tester);
      await unmountAndFlush(tester);

      expect(
        recordedCalls.map((call) => call.method),
        contains('getSessionReplayState'),
        reason: 'the change detector must reach captureScreenshot off web',
      );
    });

    testWidgets('resumes capture after recording is toggled off and on',
        (tester) async {
      await setupPosthog(replayConfig(captureNativeScreens: false));
      await pumpReplayWidget(tester);
      await tester.pump(const Duration(milliseconds: 1));

      PostHogInternalEvents.sessionRecordingActive.value = false;
      await tester.pump(const Duration(milliseconds: 1));
      recordedCalls.clear();

      PostHogInternalEvents.sessionRecordingActive.value = true;
      // start() forces the frame itself, so the restart's post-frame capture
      // fires without the test scheduling one.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        recordedCalls.map((call) => call.method),
        contains('getSessionReplayState'),
        reason: 'a recording restart must re-arm Flutter capture off web',
      );

      await unmountAndFlush(tester);
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

    testWidgets(
        'resetSessionStateIfNeeded clears every tracked view, not just the '
        'held one', (tester) async {
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

      capturer.resetSessionStateIfNeeded('session-b');

      expect(capturer.debugLastTargetStatus, isNull,
          reason: 'a stale delivery must not commit into the new session');
      capturer.confirmDelivered(imageInfo.id, metaSent: true);
      expect(status.sentMetaEvent, isTrue,
          reason: 'the dropped status is no longer written to');

      final next = await tester.runAsync(
        () => capturer.buildOcclusionPlaceholder(),
      );
      final nextStatus = capturer.debugLastTargetStatus!;
      expect(next, isNotNull);
      expect(nextStatus.sentMetaEvent, isFalse);
      expect(nextStatus.imageBytesHash, isNull,
          reason: 'the same RepaintBoundary gets a fresh status, so the new '
              'session is not deduped against the previous one');

      await unmountAndFlush(tester);
    });

    testWidgets('resetSessionStateIfNeeded keeps state for the same session id',
        (tester) async {
      final config = replayConfig(captureNativeScreens: true);
      await setupPosthog(config);
      await pumpReplayWidget(tester);

      final capturer = ScreenshotCapturer(config);
      capturer.resetSessionStateIfNeeded('session-a');
      final imageInfo = await tester.runAsync(
        () => capturer.buildOcclusionPlaceholder(),
      );
      capturer.confirmDelivered(imageInfo!.id, metaSent: true);
      final status = capturer.debugLastTargetStatus!;

      capturer.resetSessionStateIfNeeded('session-a');
      expect(capturer.debugLastTargetStatus, same(status),
          reason: 'an unchanged session keeps its meta latch and dedup hashes: '
              'dropping them costs a redundant full-screen frame every tick');

      capturer.resetSessionStateIfNeeded('session-a', force: true);
      expect(capturer.debugLastTargetStatus, isNull,
          reason: 'force resets even when the platform kept the session id');
      expect(capturer.debugReplaySessionId, 'session-a');

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

  group('new replay session', () {
    /// Drives one poll tick and renders [child], so the frame callback the
    /// tick armed actually fires: on a static screen nothing schedules a frame
    /// and the tick's callback would never run.
    Future<void> tickWithRepaint(WidgetTester tester, Widget child) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(PostHogWidget(child: child));
      await settleCapture(tester);
    }

    /// Records one session's first frame, so there is a latched meta event and
    /// a dedup hash for the next session to (wrongly) inherit.
    Future<void> deliverFirstFrame(WidgetTester tester) async {
      sessionReplayActive = true;
      await setupPosthog(replayConfig(captureNativeScreens: false));
      await pumpReplayWidget(tester);
      await settleCapture(tester);
      expect(recordedCalls.map((c) => c.method), contains('sendFullSnapshot'),
          reason: 'the first session must deliver, else there is no latched '
              'meta or dedup hash to carry over');
      recordedCalls.clear();
    }

    testWidgets('a native session rotation ships meta before the next frame',
        (tester) async {
      // The rotation Dart cannot predict: reset(), a 30-minute idle or the
      // 24-hour maximum duration rotate the session with no Dart API call at
      // all. Only the session id the capture path reads reveals it.
      await deliverFirstFrame(tester);

      sessionId = 'session-b';
      await tickWithRepaint(tester, Container(color: const Color(0xFF0000FF)));

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendMetaEvent'),
          reason: 'the new session has no meta of its own yet');
      expect(methods, contains('sendFullSnapshot'));
      expect(
        methods.indexOf('sendMetaEvent'),
        lessThan(methods.indexOf('sendFullSnapshot')),
        reason: 'meta must precede the frame it describes',
      );

      await unmountAndFlush(tester);
    });

    testWidgets(
        'startSessionRecording(resumeCurrent: false) ships meta even when the '
        'platform keeps the session id', (tester) async {
      // Android returns early from startSessionReplay while recording is
      // already active, so the session id does not change there. The explicit
      // request is the signal, exactly like the native integrations' `force`.
      await deliverFirstFrame(tester);

      await Posthog().startSessionRecording(resumeCurrent: false);
      await tickWithRepaint(tester, Container(color: const Color(0xFF0000FF)));

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

    testWidgets('reset() drops the meta latch for the post-logout session',
        (tester) async {
      // reset() rotates the session on both platforms. The mock keeps reporting
      // the same id so this pins the Dart-side drop specifically, rather than
      // the id-observation path a rotation would also trigger.
      await deliverFirstFrame(tester);

      await Posthog().reset();
      await tickWithRepaint(tester, Container(color: const Color(0xFF0000FF)));

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendMetaEvent'),
          reason: 'the post-logout session must not inherit the previous '
              "session's meta latch");
      expect(methods, contains('sendFullSnapshot'));
      expect(
        methods.indexOf('sendMetaEvent'),
        lessThan(methods.indexOf('sendFullSnapshot')),
        reason: 'meta must precede the frame it describes',
      );

      await unmountAndFlush(tester);
    });

    testWidgets('a repeated tick in the same session does not re-send meta',
        (tester) async {
      await deliverFirstFrame(tester);

      await tickWithRepaint(tester, Container(color: const Color(0xFF0000FF)));

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendFullSnapshot'),
          reason: 'the repainted screen is a new frame');
      expect(methods, isNot(contains('sendMetaEvent')),
          reason: 'the session id did not change, so its meta still stands');

      await unmountAndFlush(tester);
    });

    testWidgets('a capture crossing a rotation is dropped, not sent bare',
        (tester) async {
      // The ordering regression: a frame captured in the old session that lands
      // after the rotation would ship as full → meta → full in the new session,
      // and the leading full has no meta to render against.
      sessionReplayActive = true;
      var rotated = false;
      onSendMetaEvent = () {
        if (rotated) return;
        rotated = true;
        // What Posthog().startSessionRecording(resumeCurrent: false) triggers,
        // landing while this very capture is mid-send.
        sessionId = 'session-b';
        PostHogInternalEvents.forceReplaySessionReset.value++;
      };

      await setupPosthog(replayConfig(captureNativeScreens: false));
      await pumpReplayWidget(tester);
      await settleCapture(tester);

      var methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendMetaEvent'));
      expect(methods, isNot(contains('sendFullSnapshot')),
          reason: 'the frame belongs to the session it was captured in');

      recordedCalls.clear();
      await tickWithRepaint(tester, Container(color: const Color(0xFF0000FF)));

      methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendFullSnapshot'));
      expect(
        methods.indexOf('sendMetaEvent'),
        lessThan(methods.indexOf('sendFullSnapshot')),
        reason: "the new session's first frame is preceded by its own meta",
      );

      await unmountAndFlush(tester);
    });

    testWidgets('a same-session pause/resume does not re-send meta',
        (tester) async {
      // resumeCurrent keeps the session id, so its meta and dedup hashes are
      // still valid: resending them would cost a redundant full-screen frame.
      sessionReplayActive = true;
      await setupPosthog(replayConfig(captureNativeScreens: false));
      await pumpReplayWidget(tester);
      await settleCapture(tester);
      expect(recordedCalls.map((c) => c.method), contains('sendFullSnapshot'));

      recordedCalls.clear();
      await Posthog().stopSessionRecording();
      await Posthog().startSessionRecording();
      await settleCapture(tester);

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, isNot(contains('sendMetaEvent')));
      expect(methods, isNot(contains('sendFullSnapshot')),
          reason: 'the unchanged screen is still deduped against the frame '
              'this very session already sent');

      await unmountAndFlush(tester);
    });
  });

  group('close()/setup() reconfigure', () {
    // close() ends the native session, so what setup() starts is a new session
    // id: it needs its own meta event, and its first frame must not be deduped
    // against the pixels the previous session already sent.
    testWidgets('the new session ships meta and a full snapshot',
        (tester) async {
      sessionReplayActive = true;
      await setupPosthog(replayConfig(captureNativeScreens: false));
      await pumpReplayWidget(tester);
      await settleCapture(tester);
      expect(recordedCalls.map((c) => c.method), contains('sendFullSnapshot'),
          reason: 'the first session must deliver, else there is no latched '
              'meta or dedup hash to carry over');

      recordedCalls.clear();
      await Posthog().close();
      // close() ends the native session; the setup below starts a new one.
      sessionId = 'session-b';
      await setupPosthog(replayConfig(captureNativeScreens: false));
      await settleCapture(tester);

      final methods = recordedCalls.map((c) => c.method).toList();
      expect(methods, contains('sendMetaEvent'),
          reason: 'the new session has no meta of its own yet');
      expect(methods, contains('sendFullSnapshot'),
          reason: "the unchanged screen must still be sampled: the previous "
              "session's dedup hash may not survive into this one");
      expect(
        methods.indexOf('sendMetaEvent'),
        lessThan(methods.indexOf('sendFullSnapshot')),
        reason: 'meta must precede the frame it describes',
      );

      await unmountAndFlush(tester);
    });
  });
}
