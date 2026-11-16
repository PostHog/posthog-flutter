@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CapturePlatform platform;
  late PosthogFlutterPlatformInterface previousPlatform;

  setUp(() async {
    previousPlatform = PosthogFlutterPlatformInterface.instance;
    platform = _CapturePlatform();
    PosthogFlutterPlatformInterface.instance = platform;
    await Posthog().setup(PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = false
      ..errorTrackingConfig.capturePlatformDispatcherErrors = false);
  });

  tearDown(() async {
    await Posthog().close();
    PosthogFlutterPlatformInterface.instance = previousPlatform;
    await platform.captures.close();
  });

  test('captures an immediate background failure with its stack and metadata',
      () async {
    final exited = ReceivePort();
    final isolate = await Isolate.spawn(
      _failImmediately,
      null,
      paused: true,
      debugName: 'background-worker',
      onExit: exited.sendPort,
    );
    addTearDown(() {
      isolate.kill(priority: Isolate.immediate);
      exited.close();
    });

    final captured = platform.captures.stream.first;
    final listener = isolate.addPostHogErrorListener();
    addTearDown(() => isolate.removePostHogErrorListener(listener));
    isolate.resume(isolate.pauseCapability!);

    final call = await captured.timeout(const Duration(seconds: 10));
    await exited.first;
    expect(call.stackTrace.toString(), contains('_failImmediately'));
    expect(call.properties, {'isolate_name': 'background-worker'});

    final event = DartExceptionProcessor.processException(
      error: call.error,
      stackTrace: call.stackTrace,
      properties: call.properties,
    );
    final exception = (event['\$exception_list'] as List).single as Map;
    expect(exception['value'], 'Bad state: immediate background failure');
    expect(exception['mechanism'], containsPair('handled', false));
    expect(exception['mechanism'], containsPair('type', 'isolateError'));
    expect(event, isNot(contains('\$exception_source')));
    expect((exception['stacktrace'] as Map)['frames'], isNotEmpty);
    expect(platform.capturedExceptions, hasLength(1));

    await Future<void>.delayed(Duration.zero);
    await _expectClosed(listener);
    isolate.removePostHogErrorListener(listener);
    isolate.removePostHogErrorListener(listener);
  });

  test('cleanup stops capture without removing other error listeners',
      () async {
    final ready = ReceivePort();
    final errors = ReceivePort();
    final observed = StreamIterator<Object?>(errors);
    final isolate = await Isolate.spawn(
      _commandWorker,
      ready.sendPort,
      paused: true,
      errorsAreFatal: false,
      onError: errors.sendPort,
    );
    addTearDown(() async {
      isolate.kill(priority: Isolate.immediate);
      ready.close();
      errors.close();
      await observed.cancel();
    });

    final captures =
        StreamIterator<CapturedExceptionCall>(platform.captures.stream);
    addTearDown(captures.cancel);
    final listener = isolate.addPostHogErrorListener();
    addTearDown(() => isolate.removePostHogErrorListener(listener));
    isolate.resume(isolate.pauseCapability!);
    final commands = await ready.first as SendPort;

    for (final message in ['first failure', 'second failure']) {
      commands.send(message);
      expect(await captures.moveNext().timeout(const Duration(seconds: 10)),
          isTrue);
      expect(await observed.moveNext(), isTrue);
      expect((observed.current as List).first, contains(message));
    }

    isolate.removePostHogErrorListener(listener);
    isolate.removePostHogErrorListener(listener);
    await _expectClosed(listener);
    commands.send('after cleanup');
    expect(await observed.moveNext(), isTrue);
    expect((observed.current as List).first, contains('after cleanup'));
    await Future<void>.delayed(Duration.zero);
    expect(platform.capturedExceptions, hasLength(2));
  });

  test('only captures errors from the hooked isolate', () async {
    final ready = ReceivePort();
    final errors = ReceivePort();
    final observed = StreamIterator<Object?>(errors);
    final unhooked = await Isolate.spawn(
      _failImmediately,
      null,
      paused: true,
      onError: errors.sendPort,
    );
    final hooked = await Isolate.spawn(
      _commandWorker,
      ready.sendPort,
      paused: true,
      errorsAreFatal: false,
    );
    addTearDown(() async {
      unhooked.kill(priority: Isolate.immediate);
      hooked.kill(priority: Isolate.immediate);
      ready.close();
      errors.close();
      await observed.cancel();
    });

    final listener = hooked.addPostHogErrorListener();
    addTearDown(() => hooked.removePostHogErrorListener(listener));
    unhooked.resume(unhooked.pauseCapability!);
    expect(await observed.moveNext(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(platform.capturedExceptions, isEmpty);

    final captured = platform.captures.stream.first;
    hooked.resume(hooked.pauseCapability!);
    final commands = await ready.first as SendPort;
    commands.send('hooked worker');
    final call = await captured.timeout(const Duration(seconds: 10));
    final event = DartExceptionProcessor.processException(error: call.error);
    final exception = (event['\$exception_list'] as List).single as Map;
    expect(exception['value'], 'Bad state: hooked worker');
    expect(platform.capturedExceptions, hasLength(1));
  });
}

Future<void> _expectClosed(RawReceivePort port) async {
  var receivedMessage = false;
  port.handler = (Object? _) => receivedMessage = true;
  port.sendPort.send('closed-port probe');
  await Future<void>.delayed(Duration.zero);
  expect(receivedMessage, isFalse, reason: 'The listener port must be closed');
}

void _failImmediately(Object? _) {
  throw StateError('immediate background failure');
}

void _commandWorker(SendPort ready) {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.listen((Object? message) => throw StateError(message as String));
}

class _CapturePlatform extends PosthogFlutterPlatformFake {
  final captures = StreamController<CapturedExceptionCall>();

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {
    await super.captureException(
      error: error,
      stackTrace: stackTrace,
      properties: properties,
    );
    captures.add(capturedExceptions.last);
  }
}
