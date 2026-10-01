import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

import 'posthog_flutter_platform_interface_fake.dart';
import 'replay_capture_settle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final recordedCalls = <MethodCall>[];

  PostHogConfig replayConfig() {
    return PostHogConfig('test_project_token')
      ..sessionReplay = true
      ..sessionReplayConfig.throttleDelay = const Duration(milliseconds: 100)
      ..sessionReplayConfig.captureNativeScreens = false;
  }

  setUp(() {
    recordedCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      if (call.method == 'getSessionReplayState') {
        return {'isActive': true, 'sessionId': 'session-a'};
      }
      return null;
    });
  });

  tearDown(() async {
    await Posthog().close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  List<String> methodsOf(List<MethodCall> calls) =>
      calls.map((c) => c.method).toList();

  testWidgets(
      'disable stops Flutter replay, so a later frame is not snapshotted',
      (tester) async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    await Posthog().setup(replayConfig());
    expect(PostHogInternalEvents.sessionRecordingActive.value, isTrue);

    await tester.pumpWidget(
      PostHogWidget(child: Container(color: const Color(0xFF00FF00))),
    );
    await settleUntil(
      tester,
      () => recordedCalls.any((c) => c.method == 'sendFullSnapshot'),
    );
    expect(methodsOf(recordedCalls), contains('sendFullSnapshot'));
    recordedCalls.clear();

    await Posthog().disable();
    expect(PostHogInternalEvents.sessionRecordingActive.value, isFalse);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      PostHogWidget(child: Container(color: const Color(0xFF0000FF))),
    );
    await settleCapture(tester);

    expect(methodsOf(recordedCalls), isNot(contains('sendFullSnapshot')));
  });

  test('disable stops replay before opting out, enable starts a new recording',
      () async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
    await Posthog().setup(replayConfig());

    recordedCalls.clear();
    await Posthog().disable();

    final disabled = methodsOf(recordedCalls);
    expect(disabled, contains('stopSessionRecording'));
    expect(disabled, contains('disable'));
    expect(
      disabled.indexOf('stopSessionRecording'),
      lessThan(disabled.indexOf('disable')),
      reason: 'native stop is a no-op once the SDK is already opted out',
    );
    expect(PostHogInternalEvents.sessionRecordingActive.value, isFalse);

    recordedCalls.clear();
    await Posthog().enable();

    final enabled = methodsOf(recordedCalls);
    expect(enabled, contains('enable'));
    expect(enabled, contains('startSessionRecording'));
    expect(
      enabled.indexOf('enable'),
      lessThan(enabled.indexOf('startSessionRecording')),
      reason: 'startSessionRecording returns immediately while opted out',
    );
    final start = recordedCalls
        .firstWhere((call) => call.method == 'startSessionRecording');
    expect(start.arguments, isFalse);
    expect(PostHogInternalEvents.sessionRecordingActive.value, isTrue);
  });

  test('disable does not stop replay when it was never started', () async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
    await Posthog().setup(PostHogConfig('test_project_token'));

    recordedCalls.clear();
    await Posthog().disable();
    await Posthog().enable();

    expect(methodsOf(recordedCalls), contains('disable'));
    expect(methodsOf(recordedCalls), contains('enable'));
    expect(methodsOf(recordedCalls), isNot(contains('stopSessionRecording')));
    expect(methodsOf(recordedCalls), isNot(contains('startSessionRecording')));
    expect(PostHogInternalEvents.sessionRecordingActive.value, isFalse);
  });
}
