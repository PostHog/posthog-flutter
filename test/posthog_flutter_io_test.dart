import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';

// Converted from variable to function declaration
void emptyCallback(List<String> flags, Map<String, dynamic> flagVariants,
    {bool? errorsLoading}) {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PosthogFlutterIO posthogFlutterIO;
  late PostHogConfig testConfig;

  // For testing method calls
  final List<MethodCall> log = <MethodCall>[];
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
      // Converted to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants,
          {bool? errorsLoading}) {
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

    test(
        'invokes callback when native sends onFeatureFlagsCallback event with valid data',
        () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;

      // Converted to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants,
          {bool? errorsLoading}) {
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      final Map<String, dynamic> mockNativeArgs = {
        'flags': ['flag1', 'feature-abc'],
        'flagVariants': {'flag1': true, 'feature-abc': 'variant-x'},
        'errorsLoading': false,
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgs)),
        (ByteData? data) {},
      );

      expect(receivedFlags, equals(['flag1', 'feature-abc']));
      expect(receivedVariants,
          equals({'flag1': true, 'feature-abc': 'variant-x'}));
      expect(receivedErrorState, isFalse);
    });

    test(
        'invokes callback with default/empty data when native sends onFeatureFlagsCallback with empty map (mobile behavior)',
        () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;

      // Converted to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants,
          {bool? errorsLoading}) {
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      // Simulate mobile sending an empty map
      final Map<String, dynamic> mockNativeArgs = {};

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgs)),
        (ByteData? data) {},
      );

      expect(receivedFlags, isEmpty);
      expect(receivedVariants, isEmpty);
      expect(receivedErrorState,
          isNull); // errorsLoading will be null as it's not in the map
    });

    test(
        'invokes callback with errorsLoading true if Dart side processing fails, even with empty native args',
        () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;

      // Converted to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants,
          {bool? errorsLoading}) {
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      // Simulate native sending an argument that will cause a cast error in _handleMethodCall (before the fix)
      // For the current code, this test will verify the catch block sets errorsLoading: true
      final Map<String, dynamic> mockNativeArgsMalformed = {
        'flags': 123, // Invalid type, will cause cast error and trigger catch
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgsMalformed)),
        (ByteData? data) {},
      );

      expect(receivedFlags, isEmpty);
      expect(receivedVariants, isEmpty);
      expect(receivedErrorState, isTrue);
    });

    test(
        'handles onFeatureFlagsCallback with malformed data gracefully (e.g. wrong types in maps/lists)',
        () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;
      bool callbackInvoked = false;

      // Converted to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants,
          {bool? errorsLoading}) {
        callbackInvoked = true;
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      testConfig = PostHogConfig('test_api_key', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      final Map<String, dynamic> mockNativeArgsMalformed = {
        'flags': 'not_a_list', // This will be handled by the ?? [] for flags
        'flagVariants': [
          'not_a_map'
        ], // This will be handled by the ?? {} for variants
        'errorsLoading':
            'not_a_bool', // This will be handled by `as bool?` resulting in null or catch block
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgsMalformed)),
        (ByteData? data) {},
      );

      expect(callbackInvoked, isTrue,
          reason: "Callback should still be invoked on parse error.");
      expect(receivedFlags, isEmpty,
          reason:
              "Flags should default to empty on parse error due to type mismatch.");
      expect(receivedVariants, isEmpty,
          reason:
              "Variants should default to empty on parse error due to type mismatch.");
      expect(receivedErrorState, isTrue,
          reason:
              "errorsLoading should be true on parse error in catch block.");
    });
  });
}
