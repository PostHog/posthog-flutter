import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall)? onCall;

  setUp(() async {
    calls.clear();
    onCall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return onCall?.call(call);
    });
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
    await Posthog().close();
    calls.clear();
  });

  tearDown(() async {
    onCall = null;
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

  test(
      'runtime toggle waits for native acknowledgement and keeps replay active',
      () async {
    final config = PostHogConfig('test-token')..sessionReplay = true;
    await Posthog().setup(config);
    calls.clear();
    final acknowledged = Completer<void>();
    onCall = (call) async {
      if (call.method == 'setCaptureTouches') {
        await acknowledged.future;
      }
      return null;
    };

    var completed = false;
    final disable = Posthog().setCaptureTouches(false).then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(config.sessionReplayConfig.captureTouches, isTrue);
    acknowledged.complete();
    await disable;
    expect(config.sessionReplayConfig.captureTouches, isFalse);
    expect(PostHogInternalEvents.sessionRecordingActive.value, isTrue);

    await Posthog().setCaptureTouches(true);
    expect(config.sessionReplayConfig.captureTouches, isTrue);
    expect(calls.map((call) => call.method),
        ['setCaptureTouches', 'setCaptureTouches']);
    expect(calls.map((call) => call.arguments), [
      {'enabled': false},
      {'enabled': true},
    ]);
  });

  test('native failures propagate rather than claim touches are disabled',
      () async {
    final config = PostHogConfig('test-token');
    await Posthog().setup(config);
    onCall = (call) async {
      if (call.method == 'setCaptureTouches') {
        throw PlatformException(code: 'not_ready');
      }
      return null;
    };

    await expectLater(
        Posthog().setCaptureTouches(false), throwsA(isA<PlatformException>()));
    expect(config.sessionReplayConfig.captureTouches, isTrue);
  });

  test('missing native implementation propagates an error', () async {
    final config = PostHogConfig('test-token');
    await Posthog().setup(config);
    onCall = (call) async {
      if (call.method == 'setCaptureTouches') {
        throw MissingPluginException();
      }
      return null;
    };
    await expectLater(Posthog().setCaptureTouches(false),
        throwsA(isA<MissingPluginException>()));
    expect(config.sessionReplayConfig.captureTouches, isTrue);
  });

  test('runtime toggle before setup fails explicitly', () async {
    await expectLater(
        Posthog().setCaptureTouches(false), throwsA(isA<StateError>()));
    expect(calls, isEmpty);
  });

  test('unsupported platform cannot silently accept a privacy toggle',
      () async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    final config = PostHogConfig('test-token');
    await Posthog().setup(config);
    await expectLater(
        Posthog().setCaptureTouches(false), throwsA(isA<UnsupportedError>()));
    expect(config.sessionReplayConfig.captureTouches, isTrue);
  });
}
