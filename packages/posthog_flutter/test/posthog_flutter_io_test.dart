import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';

// Simplified void callback for feature flags
void emptyCallback() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PosthogFlutterIO posthogFlutterIO;
  late PostHogConfig testConfig;

  // For testing method calls
  final log = <MethodCall>[];
  const MethodChannel channel = MethodChannel('posthog_flutter');

  setUp(() {
    posthogFlutterIO = PosthogFlutterIO();
    log.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'isFeatureEnabled') {
        return true;
      }
      // Simulate setup call success
      if (methodCall.method == 'setup') {
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PosthogFlutterIO onFeatureFlags via setup', () {
    test(
        'setup initializes method call handler and registers callback if provided',
        () async {
      bool callbackInvoked = false;
      void testCallback() {
        callbackInvoked = true;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      // To verify handler is set, we trigger the callback from native side
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec
            .encodeMethodCall(const MethodCall('onFeatureFlagsCallback', {})),
        (ByteData? data) {},
      );
      expect(callbackInvoked, isTrue);
      expect(log.any((call) => call.method == 'setup'), isTrue);
    });

    test('invokes callback when native sends onFeatureFlagsCallback event',
        () async {
      bool callbackInvoked = false;

      void testCallback() {
        callbackInvoked = true;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      // Native sends empty map (iOS/Android behavior)
      final mockNativeArgs = <String, dynamic>{};

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgs)),
        (ByteData? data) {},
      );

      expect(callbackInvoked, isTrue);
    });

    test(
        'invokes callback when native sends onFeatureFlagsCallback with empty map (mobile behavior)',
        () async {
      bool callbackInvoked = false;

      void testCallback() {
        callbackInvoked = true;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      // Simulate mobile sending an empty map
      final mockNativeArgs = <String, dynamic>{};

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgs)),
        (ByteData? data) {},
      );

      expect(callbackInvoked, isTrue);
    });

    test('invokes callback even with malformed native args', () async {
      bool callbackInvoked = false;

      void testCallback() {
        callbackInvoked = true;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      // Simulate native sending malformed arguments - callback should still be invoked
      final mockNativeArgsMalformed = {
        'flags': 123, // Invalid type, but callback is void so it doesn't matter
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgsMalformed)),
        (ByteData? data) {},
      );

      expect(callbackInvoked, isTrue);
    });

    test('does not invoke callback when no callback is registered', () async {
      // Setup without callback
      testConfig = PostHogConfig('test_api_key');
      await posthogFlutterIO.setup(testConfig);

      // This should not throw - just silently do nothing
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec
            .encodeMethodCall(const MethodCall('onFeatureFlagsCallback', {})),
        (ByteData? data) {},
      );

      // If we get here without exception, the test passes
      expect(true, isTrue);
    });
  });
}
