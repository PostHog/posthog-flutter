import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';

// Converted from variable to function declaration
void emptyCallback(List<String> flags, Map<String, dynamic> flagVariants, {bool? errorsLoading}) {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PosthogFlutterIO posthogFlutterIO;

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
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PosthogFlutterIO onFeatureFlags', () {
    test('registers callback and initializes method call handler only once', () {
      posthogFlutterIO.onFeatureFlags(emptyCallback);

      // Converted from variable to function declaration
      void anotherCallback(List<String> flags, Map<String, dynamic> flagVariants, {bool? errorsLoading}) {}
      posthogFlutterIO.onFeatureFlags(anotherCallback);
    });

    test('invokes callback when native sends onFeatureFlagsCallback event with valid data', () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;

      // Converted from variable to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants, {bool? errorsLoading}) {
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      posthogFlutterIO.onFeatureFlags(testCallback);

      final Map<String, dynamic> mockNativeArgs = {
        'flags': ['flag1', 'feature-abc'],
        'flagVariants': {'flag1': true, 'feature-abc': 'variant-x'},
        'errorsLoading': false,
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('onFeatureFlagsCallback', mockNativeArgs)),
        (ByteData? data) {},
      );

      expect(receivedFlags, equals(['flag1', 'feature-abc']));
      expect(receivedVariants, equals({'flag1': true, 'feature-abc': 'variant-x'}));
      expect(receivedErrorState, isFalse);
    });

    test('invokes callback with empty data when native sends onFeatureFlagsCallback event with empty/null data', () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;

      // Converted from variable to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants, {bool? errorsLoading}) {
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      posthogFlutterIO.onFeatureFlags(testCallback);

      final Map<String, dynamic> mockNativeArgs = {
        'flags': [],
        'flagVariants': {},
        'errorsLoading': null,
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('onFeatureFlagsCallback', mockNativeArgs)),
        (ByteData? data) {},
      );

      expect(receivedFlags, isEmpty);
      expect(receivedVariants, isEmpty);
      expect(receivedErrorState, isNull);
    });

     test('invokes callback with errorsLoading true when native sends onFeatureFlagsCallback event with errorsLoading true', () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;

      // Converted from variable to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants, {bool? errorsLoading}) {
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      posthogFlutterIO.onFeatureFlags(testCallback);

      final Map<String, dynamic> mockNativeArgs = {
        'flags': [],
        'flagVariants': {},
        'errorsLoading': true,
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('onFeatureFlagsCallback', mockNativeArgs)),
        (ByteData? data) {},
      );

      expect(receivedFlags, isEmpty);
      expect(receivedVariants, isEmpty);
      expect(receivedErrorState, isTrue);
    });

    test('handles onFeatureFlagsCallback with malformed data gracefully (e.g. wrong types)', () async {
      List<String>? receivedFlags;
      Map<String, dynamic>? receivedVariants;
      bool? receivedErrorState;
      bool callbackInvoked = false;
      
      // Converted from variable to function declaration
      void testCallback(List<String> flags, Map<String, dynamic> flagVariants, {bool? errorsLoading}) {
        callbackInvoked = true;
        receivedFlags = flags;
        receivedVariants = flagVariants;
        receivedErrorState = errorsLoading;
      }

      posthogFlutterIO.onFeatureFlags(testCallback);

      final Map<String, dynamic> mockNativeArgsMalformed = {
        'flags': 'not_a_list',
        'flagVariants': ['not_a_map'],
        'errorsLoading': 'not_a_bool',
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('onFeatureFlagsCallback', mockNativeArgsMalformed)),
        (ByteData? data) {},
      );
      
      expect(callbackInvoked, isTrue, reason: "Callback should still be invoked on parse error.");
      expect(receivedFlags, isEmpty, reason: "Flags should default to empty on parse error");
      expect(receivedVariants, isEmpty, reason: "Variants should default to empty on parse error");
      expect(receivedErrorState, isTrue, reason: "errorsLoading should be true on parse error.");
    });

  });
}
