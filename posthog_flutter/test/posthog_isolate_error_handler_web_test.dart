// The install regression needs `flutter test --platform chrome --wasm`:
// dart2js selects the no-op web isolate handler regardless.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  tearDown(PostHogErrorTrackingAutoCaptureIntegration.uninstall);

  test('install with captureIsolateErrors does not throw on web', () {
    final config = PostHogErrorTrackingConfig()..captureIsolateErrors = true;

    final integration = PostHogErrorTrackingAutoCaptureIntegration.install(
      config: config,
      posthog: PosthogFlutterPlatformFake(),
    );

    expect(integration, isNotNull);
  });
}
