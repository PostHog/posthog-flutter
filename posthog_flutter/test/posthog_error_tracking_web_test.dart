@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'package:posthog_flutter/src/posthog_config.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('platform error capture is skipped without disabling Flutter errors',
      () {
    final originalHandler = FlutterError.onError;
    final originalPlatformHandler = PlatformDispatcher.instance.onError;
    var forwarded = 0;
    FlutterError.onError = (_) => forwarded++;
    addTearDown(() {
      PostHogErrorTrackingAutoCaptureIntegration.uninstall();
      FlutterError.onError = originalHandler;
    });
    final posthog = PosthogFlutterPlatformFake();
    final config = PostHogErrorTrackingConfig()
      ..captureFlutterErrors = true
      ..capturePlatformDispatcherErrors = true;

    for (var i = 0; i < 2; i++) {
      final integration = PostHogErrorTrackingAutoCaptureIntegration.install(
        config: config,
        posthog: posthog,
      );
      expect(integration, isNotNull);
      expect(
          PlatformDispatcher.instance.onError, same(originalPlatformHandler));
      FlutterError.onError!(FlutterErrorDetails(
        exception: StateError('web error'),
        stack: StackTrace.current,
      ));
      PostHogErrorTrackingAutoCaptureIntegration.uninstall();
    }

    expect(posthog.capturedExceptions, hasLength(2));
    expect(forwarded, 2);
  });
}
