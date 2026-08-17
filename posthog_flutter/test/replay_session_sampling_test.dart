import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

import 'posthog_flutter_platform_interface_fake.dart';

/// A poll tick only reaches the capture path from a post-frame callback, so on a
/// screen that never repaints nothing samples unless something forces a frame.
/// `WidgetTester.pump` reproduces that faithfully: it only draws when a frame
/// has been scheduled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final recordedCalls = <MethodCall>[];
  var sessionReplayActive = false;
  String? sessionId = 'session-a';
  var rotateOnStateRead = false;

  void mockChannel() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      switch (call.method) {
        case 'getSessionReplayState':
          if (rotateOnStateRead) {
            sessionId = 'session-b';
            rotateOnStateRead = false;
          }
          return {'isActive': sessionReplayActive, 'sessionId': sessionId};
        default:
          return null;
      }
    });
  }

  PostHogConfig replayConfig() {
    return PostHogConfig('test_project_token')
      ..sessionReplay = true
      ..sessionReplayConfig.captureNativeScreens = false;
  }

  Future<void> settleCapture(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
  }

  /// One poll tick plus a repaint, so the tick's frame callback actually runs.
  Future<void> tickWithRepaint(WidgetTester tester, Widget child) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(PostHogWidget(child: child));
    await settleCapture(tester);
  }

  /// A poll tick on a completely static screen: no repaint, no new widget.
  Future<void> tickStatic(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await settleCapture(tester);
  }

  Future<void> unmountAndFlush(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> deliverFirstFrame(WidgetTester tester) async {
    sessionReplayActive = true;
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    await Posthog().setup(replayConfig());
    await tester.pumpWidget(
      PostHogWidget(child: Container(color: const Color(0xFF00FF00))),
    );
    await settleCapture(tester);
    expect(recordedCalls.map((c) => c.method), contains('sendFullSnapshot'));
    recordedCalls.clear();
  }

  List<String> methodsOf(List<MethodCall> calls) =>
      calls.map((c) => c.method).toList();

  setUp(() {
    recordedCalls.clear();
    sessionReplayActive = false;
    sessionId = 'session-a';
    rotateOnStateRead = false;
    mockChannel();
  });

  tearDown(() async {
    await Posthog().close();
    PostHogInternalEvents.nativeOcclusionEpisode = 0;
    PostHogInternalEvents.nativeOcclusionActive = false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'a tick that observes a session rotation asks for another sample, so a '
      'screen that goes static after the rotation is still resampled',
      (tester) async {
    await deliverFirstFrame(tester);

    // The native SDK rotated behind Dart's back (idle or max-duration expiry);
    // the next state read is the first thing that sees the new id.
    rotateOnStateRead = true;
    await tickWithRepaint(tester, Container(color: const Color(0xFF0000FF)));

    final stateReads =
        methodsOf(recordedCalls).where((m) => m == 'getSessionReplayState');
    expect(stateReads.length, greaterThanOrEqualTo(2),
        reason: 'the rotation must schedule a follow-up sample, since the '
            'observing tick can drop its own frame and no further tick runs '
            'on a static screen');

    await unmountAndFlush(tester);
  });

  testWidgets('reset() captures the new session on a static screen',
      (tester) async {
    await deliverFirstFrame(tester);

    await Posthog().reset();
    await tickStatic(tester);

    final methods = methodsOf(recordedCalls);
    expect(methods, contains('sendMetaEvent'));
    expect(methods, contains('sendFullSnapshot'));
    expect(methods.indexOf('sendMetaEvent'),
        lessThan(methods.indexOf('sendFullSnapshot')));

    await unmountAndFlush(tester);
  });

  testWidgets(
      'reset() still captures the new session when the platform reports replay '
      'inactive for the first sample', (tester) async {
    // The iOS shape: PostHogSDK.reset() ends the session without starting one,
    // and iOS reports replay inactive while there is no session id, so the
    // forced reset's own sample captures nothing. Android starts the new
    // session inside reset(), so it never sees this.
    await deliverFirstFrame(tester);

    var inactiveReadsLeft = 1;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      if (call.method == 'getSessionReplayState') {
        if (inactiveReadsLeft > 0) {
          inactiveReadsLeft--;
          return {'isActive': false, 'sessionId': null};
        }
        return {'isActive': true, 'sessionId': 'session-b'};
      }
      return null;
    });

    await Posthog().reset();
    await tickStatic(tester);
    await tickStatic(tester);

    final methods = methodsOf(recordedCalls);
    expect(methods, contains('sendMetaEvent'),
        reason:
            'a retry must cover the sample spent while replay was inactive');
    expect(methods, contains('sendFullSnapshot'));

    await unmountAndFlush(tester);
    mockChannel();
  });

  testWidgets(
      'a reset landing mid-capture still captures the new session on a static '
      'screen', (tester) async {
    // The frame in flight was tagged with the old session, so it is dropped
    // rather than sent. The retries the reset armed are the only thing left to
    // capture the session that replaced it.
    await deliverFirstFrame(tester);

    var armed = false;
    var inactiveReadsLeft = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      if (call.method == 'getSessionReplayState') {
        if (!armed) {
          armed = true;
          // Fires after this tick has adopted session-a and while the frame is
          // still being built, so the finished frame belongs to the session the
          // reset just replaced.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            inactiveReadsLeft = 1;
            Posthog().reset();
          });
          return {'isActive': true, 'sessionId': 'session-a'};
        }
        if (inactiveReadsLeft > 0) {
          inactiveReadsLeft--;
          return {'isActive': false, 'sessionId': null};
        }
        return {'isActive': true, 'sessionId': 'session-b'};
      }
      return null;
    });

    await tickWithRepaint(tester, Container(color: const Color(0xFF0000FF)));
    await tickStatic(tester);
    await tickStatic(tester);

    expect(methodsOf(recordedCalls), contains('sendFullSnapshot'),
        reason: 'the dropped frame must not cancel the retries that cover the '
            'session which replaced it');

    await unmountAndFlush(tester);
    mockChannel();
  });

  testWidgets(
      'an occlusion episode ending still captures when the platform reports '
      'replay inactive for the first sample', (tester) async {
    // Same cover as a forced reset gets: every out-of-band sample goes through
    // _ensureSampleLands, so none of them is a single unretried shot.
    await deliverFirstFrame(tester);

    var inactiveReadsLeft = 1;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      if (call.method == 'getSessionReplayState') {
        if (inactiveReadsLeft > 0) {
          inactiveReadsLeft--;
          return {'isActive': false, 'sessionId': null};
        }
        return {'isActive': true, 'sessionId': sessionId};
      }
      return null;
    });

    PostHogInternalEvents.nativeOcclusionActive = false;
    PostHogInternalEvents.nativeOcclusionEpisode = 1;
    PostHogInternalEvents.nativeOcclusionEvent.value++;
    await tester.pump(const Duration(milliseconds: 1));
    await settleCapture(tester);
    await tickStatic(tester);

    expect(methodsOf(recordedCalls), contains('sendFullSnapshot'),
        reason: 'the replay would otherwise stay frozen on the episode\'s last '
            'frame until the app happens to repaint');

    await unmountAndFlush(tester);
    mockChannel();
  });

  testWidgets(
      'startSessionRecording(resumeCurrent: false) captures the restarted '
      'recording on a static screen', (tester) async {
    await deliverFirstFrame(tester);

    await Posthog().startSessionRecording(resumeCurrent: false);
    await tickStatic(tester);

    final methods = methodsOf(recordedCalls);
    expect(methods, contains('sendMetaEvent'));
    expect(methods, contains('sendFullSnapshot'));

    await unmountAndFlush(tester);
  });

  testWidgets('a sample requested during an in-flight capture is retried',
      (tester) async {
    final hold = Completer<void>();
    var held = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      switch (call.method) {
        case 'getSessionReplayState':
          return {'isActive': sessionReplayActive, 'sessionId': sessionId};
        case 'sendFullSnapshot':
          if (!held) {
            held = true;
            await hold.future;
          }
          return null;
        default:
          return null;
      }
    });

    sessionReplayActive = true;
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    await Posthog().setup(replayConfig());
    await tester.pumpWidget(
      PostHogWidget(child: Container(color: const Color(0xFF00FF00))),
    );
    await settleCapture(tester);
    expect(held, isTrue, reason: 'a capture must be parked in flight');
    recordedCalls.clear();

    // The occlusion-end path requests an immediate sample while that capture is
    // still in flight, so the `_isCapturing` guard would otherwise drop it.
    PostHogInternalEvents.nativeOcclusionActive = false;
    PostHogInternalEvents.nativeOcclusionEpisode = 1;
    PostHogInternalEvents.nativeOcclusionEvent.value++;
    await tester.pump(const Duration(milliseconds: 1));

    hold.complete();
    await settleCapture(tester);
    await settleCapture(tester);

    expect(methodsOf(recordedCalls), contains('sendFullSnapshot'),
        reason: 'the deferred sample must run once the capture finishes');

    await unmountAndFlush(tester);
    mockChannel();
  });
}
