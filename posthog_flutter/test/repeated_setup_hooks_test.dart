import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PosthogFlutterPlatformFake platform;
  FlutterExceptionHandler? originalFlutterHandler;
  ErrorCallback? originalPlatformHandler;

  setUp(() async {
    platform = PosthogFlutterPlatformFake();
    PosthogFlutterPlatformInterface.instance = platform;
    await Posthog().close();
    originalFlutterHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    if (!kIsWeb) {
      originalPlatformHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (_, __) => true;
    }
  });

  tearDown(() async {
    await Posthog().close();
    FlutterError.onError = originalFlutterHandler;
    if (!kIsWeb) {
      PlatformDispatcher.instance.onError = originalPlatformHandler;
    }
  });

  void reportFlutterError({bool silent = false}) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: StateError('repeated setup repro'),
      stack: StackTrace.current,
      silent: silent,
    ));
  }

  for (final reuseConfig in [false, true]) {
    test('disables Flutter hook on repeated setup (reuse=$reuseConfig)',
        () async {
      final upstream = FlutterError.onError;
      final first = PostHogConfig('test-token')
        ..errorTrackingConfig.captureFlutterErrors = true;
      await Posthog().setup(first);
      reportFlutterError();
      expect(platform.capturedExceptions, hasLength(1));
      platform.capturedExceptions.clear();

      final second = reuseConfig ? first : PostHogConfig('test-token');
      second.errorTrackingConfig.captureFlutterErrors = false;
      await Posthog().setup(second);
      expect(Posthog().config, same(second));

      reportFlutterError();
      expect(platform.capturedExceptions, isEmpty);
      expect(FlutterError.onError, same(upstream));
    });
  }

  test('disables PlatformDispatcher hook on repeated setup', () async {
    final upstream = PlatformDispatcher.instance.onError;
    final first = PostHogConfig('test-token')
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true;
    await Posthog().setup(first);
    PlatformDispatcher.instance.onError!(
        StateError('before'), StackTrace.current);
    expect(platform.capturedExceptions, hasLength(1));
    platform.capturedExceptions.clear();

    await Posthog().setup(PostHogConfig('test-token'));
    PlatformDispatcher.instance.onError!(
        StateError('after'), StackTrace.current);
    expect(platform.capturedExceptions, isEmpty);
    expect(PlatformDispatcher.instance.onError, same(upstream));
  }, skip: kIsWeb);

  test('adds PlatformDispatcher hook while Flutter hook is installed',
      () async {
    final first = PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Posthog().setup(first);

    final second = PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true;
    await Posthog().setup(second);
    expect(Posthog().config, same(second));

    PlatformDispatcher.instance.onError!(
        StateError('after'), StackTrace.current);
    expect(platform.capturedExceptions, hasLength(1));
  }, skip: kIsWeb);

  test('replaces silent-error policy on repeated setup', () async {
    final first = PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Posthog().setup(first);

    final second = PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true
      ..errorTrackingConfig.captureSilentFlutterErrors = true;
    await Posthog().setup(second);

    reportFlutterError(silent: true);
    expect(platform.capturedExceptions, hasLength(1));
  });

  test('mutating the original silent-error policy takes effect', () async {
    final config = PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Posthog().setup(config);
    config.errorTrackingConfig.captureSilentFlutterErrors = true;
    await Posthog().setup(config);

    reportFlutterError(silent: true);
    expect(platform.capturedExceptions, hasLength(1));
  });

  test('first installation can happen on second setup', () async {
    await Posthog().setup(PostHogConfig('test-token'));
    await Posthog().setup(PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true);

    reportFlutterError();
    expect(platform.capturedExceptions, hasLength(1));
  });

  test('identical repeated setup does not duplicate capture', () async {
    final config = PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true;
    await Posthog().setup(config);
    await Posthog().setup(config);

    reportFlutterError();
    expect(platform.capturedExceptions, hasLength(1));
  });

  for (final platformHandler in [false, true]) {
    test(
        'repeated setup preserves wrapped handlers (platform=$platformHandler)',
        () async {
      var upstreamCalls = 0;
      var wrapperCalls = 0;
      final config = PostHogConfig('test-token')
        ..errorTrackingConfig.captureFlutterErrors = !platformHandler
        ..errorTrackingConfig.capturePlatformDispatcherErrors = platformHandler;

      if (platformHandler) {
        PlatformDispatcher.instance.onError = (_, __) {
          upstreamCalls++;
          return true;
        };
      } else {
        FlutterError.onError = (_) => upstreamCalls++;
      }
      await Posthog().setup(config);
      if (platformHandler) {
        final delegate = PlatformDispatcher.instance.onError!;
        PlatformDispatcher.instance.onError = (error, stack) {
          wrapperCalls++;
          return delegate(error, stack);
        };
      } else {
        final delegate = FlutterError.onError!;
        FlutterError.onError = (details) {
          wrapperCalls++;
          delegate(details);
        };
      }

      for (var i = 0; i < 3; i++) {
        await Posthog().setup(config);
      }
      if (platformHandler) {
        expect(
          PlatformDispatcher.instance.onError!(
              StateError('after'), StackTrace.current),
          isTrue,
        );
      } else {
        reportFlutterError();
      }
      expect(platform.capturedExceptions, hasLength(1));
      expect(upstreamCalls, 1);
      expect(wrapperCalls, 1);
    }, skip: kIsWeb && platformHandler);
  }

  test('close then setup applies changed hook flags', () async {
    await Posthog().setup(PostHogConfig('test-token')
      ..errorTrackingConfig.captureFlutterErrors = true);
    await Posthog().close();
    await Posthog().setup(PostHogConfig('test-token')
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true);

    reportFlutterError();
    expect(platform.capturedExceptions, isEmpty);
    PlatformDispatcher.instance.onError!(
        StateError('after'), StackTrace.current);
    expect(platform.capturedExceptions, hasLength(1));
  }, skip: kIsWeb);
}
