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
      void testCallback() {}

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

  group('getFeatureFlagResult', () {
    late PosthogFlutterPlatformFake fakePlatformInterface;

    setUp(() {
      fakePlatformInterface = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fakePlatformInterface;
    });

    test('returns null for non-existent flag', () async {
      final result = await Posthog().getFeatureFlagResult('non-existent');
      expect(result, isNull);
    });

    test('returns correct result for boolean flag (true)', () async {
      fakePlatformInterface.featureFlagValues['bool-flag'] = true;

      final result = await Posthog().getFeatureFlagResult('bool-flag');

      expect(result, isNotNull);
      expect(result!.key, equals('bool-flag'));
      expect(result.enabled, isTrue);
      expect(result.variant, isNull);
      expect(result.payload, isNull);
    });

    test('returns correct result for boolean flag (false)', () async {
      fakePlatformInterface.featureFlagValues['disabled-flag'] = false;

      final result = await Posthog().getFeatureFlagResult('disabled-flag');

      expect(result, isNotNull);
      expect(result!.key, equals('disabled-flag'));
      expect(result.enabled, isFalse);
      expect(result.variant, isNull);
    });

    test('returns correct result for multivariate flag', () async {
      fakePlatformInterface.featureFlagValues['multi-flag'] = 'variant-a';

      final result = await Posthog().getFeatureFlagResult('multi-flag');

      expect(result, isNotNull);
      expect(result!.key, equals('multi-flag'));
      expect(result.enabled, isTrue);
      expect(result.variant, equals('variant-a'));
    });

    test('includes payload when present', () async {
      fakePlatformInterface.featureFlagValues['flag-with-payload'] = true;
      fakePlatformInterface.featureFlagPayloads['flag-with-payload'] = {
        'discount': 10,
        'message': 'Welcome!',
      };

      final result = await Posthog().getFeatureFlagResult('flag-with-payload');

      expect(result, isNotNull);
      expect(result!.payload, isNotNull);
      expect(result.payload, isA<Map>());
      final payload = result.payload as Map;
      expect(payload['discount'], equals(10));
      expect(payload['message'], equals('Welcome!'));
    });

    test('multivariate flag with payload', () async {
      fakePlatformInterface.featureFlagValues['multi-with-payload'] = 'control';
      fakePlatformInterface.featureFlagPayloads['multi-with-payload'] = [
        1,
        2,
        3
      ];

      final result = await Posthog().getFeatureFlagResult('multi-with-payload');

      expect(result, isNotNull);
      expect(result!.enabled, isTrue);
      expect(result.variant, equals('control'));
      expect(result.payload, equals([1, 2, 3]));
    });

    test('returns result for flag with null value', () async {
      // Flag exists but has null value - should return a result, not null
      fakePlatformInterface.featureFlagValues['null-value-flag'] = null;

      final result = await Posthog().getFeatureFlagResult('null-value-flag');

      expect(result, isNotNull);
      expect(result!.key, equals('null-value-flag'));
      expect(result.enabled, isFalse);
    });

    test('passes sendEvent=true by default', () async {
      fakePlatformInterface.featureFlagValues['test'] = true;

      await Posthog().getFeatureFlagResult('test');

      expect(fakePlatformInterface.getFeatureFlagResultCalls.last['sendEvent'],
          isTrue);
    });

    test('passes sendEvent=false when specified', () async {
      fakePlatformInterface.featureFlagValues['test'] = true;

      await Posthog().getFeatureFlagResult('test', sendEvent: false);

      expect(fakePlatformInterface.getFeatureFlagResultCalls.last['sendEvent'],
          isFalse);
    });
  });

  group('PostHogFeatureFlagResult', () {
    test('equality', () {
      final result1 = PostHogFeatureFlagResult(
        key: 'flag',
        enabled: true,
        variant: 'a',
        payload: 1,
      );
      final result2 = PostHogFeatureFlagResult(
        key: 'flag',
        enabled: true,
        variant: 'a',
        payload: 1,
      );
      final result3 = PostHogFeatureFlagResult(
        key: 'flag',
        enabled: true,
        variant: 'b',
        payload: 1,
      );

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });

    test('toString', () {
      final result = PostHogFeatureFlagResult(
        key: 'my-flag',
        enabled: true,
        variant: 'test',
        payload: null,
      );

      expect(
        result.toString(),
        equals(
            'PostHogFeatureFlagResult(key: my-flag, enabled: true, variant: test, payload: null)'),
      );
    });

    test('fromMap returns null for null input', () {
      final result = PostHogFeatureFlagResult.fromMap(null, 'fallback');
      expect(result, isNull);
    });

    test('fromMap returns null for non-Map input', () {
      final result = PostHogFeatureFlagResult.fromMap('not a map', 'fallback');
      expect(result, isNull);
    });

    test('fromMap parses valid map', () {
      final map = {
        'key': 'my-flag',
        'enabled': true,
        'variant': 'test-variant',
        'payload': {'data': 123},
      };

      final result = PostHogFeatureFlagResult.fromMap(map, 'fallback');

      expect(result, isNotNull);
      expect(result!.key, equals('my-flag'));
      expect(result.enabled, isTrue);
      expect(result.variant, equals('test-variant'));
      expect(result.payload, equals({'data': 123}));
    });

    test('fromMap uses fallback key when map key is null', () {
      final map = {
        'enabled': true,
        'variant': null,
        'payload': null,
      };

      final result = PostHogFeatureFlagResult.fromMap(map, 'fallback-key');

      expect(result, isNotNull);
      expect(result!.key, equals('fallback-key'));
    });

    test('fromMap defaults enabled to false when not in map', () {
      final map = <String, dynamic>{
        'key': 'my-flag',
      };

      final result = PostHogFeatureFlagResult.fromMap(map, 'fallback');

      expect(result, isNotNull);
      expect(result!.enabled, isFalse);
    });
  });
}
