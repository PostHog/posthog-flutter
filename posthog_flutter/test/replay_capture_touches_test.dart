import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
    await Posthog().close();
    calls.clear();
  });

  tearDown(() async {
    await Posthog().close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('touch capture defaults to enabled in the native setup map', () {
    expect(PostHogSessionReplayConfig().toMap()['captureTouches'], isTrue);
  });

  test('setup forwards disabled touch capture without disabling replay',
      () async {
    final config = PostHogConfig('test-token')
      ..sessionReplay = true
      ..sessionReplayConfig.captureTouches = false;
    await Posthog().setup(config);

    final setup = calls.singleWhere((call) => call.method == 'setup');
    final arguments = setup.arguments as Map<Object?, Object?>;
    final replayConfig =
        arguments['sessionReplayConfig'] as Map<Object?, Object?>;
    expect(arguments['sessionReplay'], isTrue);
    expect(replayConfig['captureTouches'], isFalse);
    expect(PostHogInternalEvents.sessionRecordingActive.value, isTrue);
  });

  test('a fresh setup after close restores the default touch setting',
      () async {
    await Posthog().setup(PostHogConfig('test-token')
      ..sessionReplayConfig.captureTouches = false);
    await Posthog().close();
    calls.clear();
    await Posthog().setup(PostHogConfig('test-token'));

    final setup = calls.singleWhere((call) => call.method == 'setup');
    final arguments = setup.arguments as Map<Object?, Object?>;
    final replayConfig =
        arguments['sessionReplayConfig'] as Map<Object?, Object?>;
    expect(replayConfig['captureTouches'], isTrue);
  });
}
