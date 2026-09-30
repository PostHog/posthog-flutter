import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'package:posthog_flutter/src/posthog_config.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platformHandler in [false, true]) {
    group(
        platformHandler ? 'PlatformDispatcher.onError' : 'FlutterError.onError',
        () {
      late FlutterExceptionHandler? savedFlutterHandler;
      late ErrorCallback? savedPlatformHandler;
      late PostHogErrorTrackingConfig config;
      late PosthogFlutterPlatformFake posthog;
      late PostHogErrorTrackingAutoCaptureIntegration integration;
      late bool Function() dispatch;
      var upstreamCalls = 0;
      var wrapperCalls = 0;

      setUp(() {
        savedFlutterHandler = FlutterError.onError;
        savedPlatformHandler = PlatformDispatcher.instance.onError;
        upstreamCalls = 0;
        wrapperCalls = 0;
        posthog = PosthogFlutterPlatformFake();
        config = PostHogErrorTrackingConfig()
          ..captureFlutterErrors = !platformHandler
          ..capturePlatformDispatcherErrors = platformHandler;

        if (platformHandler) {
          PlatformDispatcher.instance.onError = (error, stack) {
            upstreamCalls++;
            return true;
          };
        } else {
          FlutterError.onError = (details) => upstreamCalls++;
        }
        integration = PostHogErrorTrackingAutoCaptureIntegration.install(
          config: config,
          posthog: posthog,
        )!;

        if (platformHandler) {
          final previous = PlatformDispatcher.instance.onError!;
          PlatformDispatcher.instance.onError = (error, stack) {
            if (++wrapperCalls > 1) {
              throw StateError('handler chain recursed');
            }
            return previous(error, stack);
          };
          dispatch = () => PlatformDispatcher.instance.onError!(
                StateError('handler lifecycle repro'),
                StackTrace.current,
              );
        } else {
          final previous = FlutterError.onError!;
          FlutterError.onError = (details) {
            if (++wrapperCalls > 1) {
              throw StateError('handler chain recursed');
            }
            previous(details);
          };
          dispatch = () {
            FlutterError.onError!(FlutterErrorDetails(
              exception: StateError('handler lifecycle repro'),
              stack: StackTrace.current,
            ));
            return true;
          };
        }
      });

      tearDown(() {
        PostHogErrorTrackingAutoCaptureIntegration.uninstall();
        FlutterError.onError = savedFlutterHandler;
        PlatformDispatcher.instance.onError = savedPlatformHandler;
      });

      test('installed handler captures once and preserves the upstream chain',
          () {
        final handled = dispatch();

        expect(posthog.capturedExceptions, hasLength(1));
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('uninstall restores a null upstream handler', () {
        PostHogErrorTrackingAutoCaptureIntegration.uninstall();
        if (platformHandler) {
          PlatformDispatcher.instance.onError = null;
        } else {
          FlutterError.onError = null;
        }
        PostHogErrorTrackingAutoCaptureIntegration.install(
          config: config,
          posthog: posthog,
        );

        final handled = dispatch();
        expect(posthog.capturedExceptions, hasLength(1));
        if (platformHandler) expect(handled, isFalse);

        PostHogErrorTrackingAutoCaptureIntegration.uninstall();

        expect(
          platformHandler
              ? PlatformDispatcher.instance.onError
              : FlutterError.onError,
          isNull,
        );
      });

      test('uninstall preserves the upstream handler chain', () {
        PostHogErrorTrackingAutoCaptureIntegration.uninstall();

        final handled = dispatch();

        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('uninstall stops captures from a retained handler', () {
        PostHogErrorTrackingAutoCaptureIntegration.uninstall();

        dispatch();

        expect(posthog.capturedExceptions, isEmpty);
      });

      test('restart captures once without a circular handler chain', () {
        integration.stop();
        integration.start();

        final handled = dispatch();

        expect(posthog.capturedExceptions, hasLength(1));
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('repeated reinstalls leave only the current integration capturing',
          () {
        final retiredPlatforms = [posthog];
        for (var i = 0; i < 3; i++) {
          PostHogErrorTrackingAutoCaptureIntegration.uninstall();
          posthog = PosthogFlutterPlatformFake();
          PostHogErrorTrackingAutoCaptureIntegration.install(
            config: config,
            posthog: posthog,
          );
          if (i < 2) retiredPlatforms.add(posthog);
        }

        final handled = dispatch();

        expect(posthog.capturedExceptions, hasLength(1));
        for (final retired in retiredPlatforms) {
          expect(retired.capturedExceptions, isEmpty);
        }
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });

      test('reinstall captures once and preserves the upstream chain', () {
        PostHogErrorTrackingAutoCaptureIntegration.uninstall();
        PostHogErrorTrackingAutoCaptureIntegration.install(
          config: config,
          posthog: posthog,
        );

        final handled = dispatch();

        expect(posthog.capturedExceptions, hasLength(1));
        expect(wrapperCalls, 1);
        expect(upstreamCalls, 1);
        expect(handled, isTrue);
      });
    });
  }
}
