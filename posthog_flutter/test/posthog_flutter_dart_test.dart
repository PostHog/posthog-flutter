import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter_dart.dart';
import 'package:posthog_flutter/src/posthog_flutter_desktop.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  test('registerWith installs the Windows and Linux implementation', () {
    // Seed a known instance first: reading the uninitialized default would
    // construct the method-channel implementation, which needs a Flutter
    // binding.
    final previous = PosthogFlutterPlatformFake();
    PosthogFlutterPlatformInterface.instance = previous;
    addTearDown(() => PosthogFlutterPlatformInterface.instance = previous);

    PosthogFlutterDart.registerWith();

    expect(
      PosthogFlutterPlatformInterface.instance,
      isA<PosthogFlutterDesktop>(),
    );
  });
}
