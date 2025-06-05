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

    test('onFeatureFlags registers callback with platform interface', () {
      // ignore: prefer_function_declarations_over_variables
      final OnFeatureFlagsCallback testCallback =
          (flags, flagVariants, {errorsLoading}) {};

      Posthog().onFeatureFlags(testCallback);

      expect(fakePlatformInterface.registeredOnFeatureFlagsCallback,
          equals(testCallback));
    });
  });
}
