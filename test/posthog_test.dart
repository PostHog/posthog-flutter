import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Posthog', () {
    late PosthogFlutterPlatformFake fakePlatformInterface;

    setUp(() {
      fakePlatformInterface = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fakePlatformInterface;
    });

    test(
        'setup passes config and onFeatureFlags callback to platform interface',
        () async {
      // ignore: prefer_function_declarations_over_variables
      final OnFeatureFlagsCallback testCallback =
          (flags, flagVariants, {errorsLoading}) {};

      final config = PostHogConfig(
        'test_api_key',
        onFeatureFlags: testCallback,
      );

      await Posthog().setup(config);

      expect(fakePlatformInterface.receivedConfig, equals(config));
      expect(fakePlatformInterface.registeredOnFeatureFlagsCallback,
          equals(testCallback));
    });
  });
}
