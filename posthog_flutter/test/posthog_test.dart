import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Posthog', () {
    late PosthogFlutterPlatformFake fakePlatformInterface;

    setUp(() async {
      fakePlatformInterface = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fakePlatformInterface;
      await Posthog().close();
    });

    test(
      'setup passes config and onFeatureFlags callback to platform interface',
      () async {
        void testCallback() {}

        final config = PostHogConfig(
          'test_project_token',
          onFeatureFlags: testCallback,
        );

        await Posthog().setup(config);

        expect(fakePlatformInterface.receivedConfig, equals(config));
        expect(
          fakePlatformInterface.registeredOnFeatureFlagsCallback,
          equals(testCallback),
        );
      },
    );

    group('setup with blank project token', () {
      const blankProjectTokens = <String, String>{
        'empty string': '',
        'space': ' ',
        'tab': '\t',
        'mixed whitespace': ' \n\t ',
      };

      for (final entry in blankProjectTokens.entries) {
        test('skips platform setup and integrations for ${entry.key}',
            () async {
          final originalFlutterErrorHandler = FlutterError.onError;
          void sentinelHandler(FlutterErrorDetails _) {}
          FlutterError.onError = sentinelHandler;

          try {
            final config = PostHogConfig(entry.value);
            config.sessionReplay = true;
            config.errorTrackingConfig.captureFlutterErrors = true;

            await Posthog().setup(config);

            expect(fakePlatformInterface.receivedConfig, isNull);
            expect(Posthog().config, isNull);
            expect(PostHogInternalEvents.sessionRecordingActive.value, isFalse);
            expect(FlutterError.onError, same(sentinelHandler));
          } finally {
            FlutterError.onError = originalFlutterErrorHandler;
          }
        });
      }
    });

    test(
      'enable reinstalls Flutter error autocapture after disable',
      () async {
        final originalFlutterErrorHandler = FlutterError.onError;
        FlutterError.onError = (_) {};

        try {
          final config = PostHogConfig('test_project_token');
          config.errorTrackingConfig.captureFlutterErrors = true;
          await Posthog().setup(config);

          FlutterError.reportError(
            FlutterErrorDetails(
              exception: Exception('before-disable'),
              context: ErrorDescription('issue 381 repro'),
            ),
          );
          expect(fakePlatformInterface.capturedExceptions.length, 1);

          fakePlatformInterface.capturedExceptions.clear();
          await Posthog().disable();

          FlutterError.reportError(
            FlutterErrorDetails(
              exception: Exception('while-disabled'),
              context: ErrorDescription('issue 381 repro'),
            ),
          );
          expect(fakePlatformInterface.capturedExceptions, isEmpty);

          await Posthog().enable();

          FlutterError.reportError(
            FlutterErrorDetails(
              exception: Exception('after-enable'),
              context: ErrorDescription('issue 381 repro'),
            ),
          );
          expect(fakePlatformInterface.capturedExceptions.length, 1);
        } finally {
          await Posthog().disable();
          FlutterError.onError = originalFlutterErrorHandler;
        }
      },
    );
  });

  group('PostHogConfig', () {
    test('trims whitespace-sensitive config values in config and toMap', () {
      final config = PostHogConfig(' \n test_project_token\t ');
      config.host = ' \nhttps://eu.i.posthog.com/\t ';

      expect(config.projectToken, equals('test_project_token'));
      expect(config.apiKey, equals('test_project_token'));
      expect(config.host, equals('https://eu.i.posthog.com/'));
      expect(config.toMap()['projectToken'], equals('test_project_token'));
      expect(config.toMap()['apiKey'], equals('test_project_token'));
      expect(config.toMap()['host'], equals('https://eu.i.posthog.com/'));
    });

    test('defaults a blank host after trimming whitespace', () {
      final config = PostHogConfig('test_project_token');
      config.host = ' \n\t ';

      expect(config.host, equals('https://us.i.posthog.com'));
      expect(config.toMap()['host'], equals('https://us.i.posthog.com'));
    });

    test('session replay masks all platform views by default', () {
      final config = PostHogConfig('test_project_token');

      expect(config.sessionReplayConfig.maskAllPlatformViews, isTrue);

      final replayConfig =
          config.toMap()['sessionReplayConfig'] as Map<String, dynamic>;
      expect(replayConfig.containsKey('maskAllPlatformViews'), isTrue);
      expect(replayConfig['maskAllPlatformViews'], isTrue);

      config.sessionReplayConfig.maskAllPlatformViews = false;

      final updatedReplayConfig =
          config.toMap()['sessionReplayConfig'] as Map<String, dynamic>;
      expect(updatedReplayConfig['maskAllPlatformViews'], isFalse);
    });

    test('omits bootstrap from toMap when not set', () {
      final config = PostHogConfig('test_project_token');

      expect(config.bootstrap, isNull);
      expect(config.toMap().containsKey('bootstrap'), isFalse);
    });

    test('serializes an identified identity bootstrap', () {
      final config = PostHogConfig('test_project_token')
        ..bootstrap = const PostHogBootstrapConfig(
          distinctId: 'user-123',
          isIdentifiedId: true,
        );

      final bootstrap = config.toMap()['bootstrap'] as Map<String, dynamic>;
      expect(bootstrap['distinctId'], equals('user-123'));
      expect(bootstrap['isIdentifiedId'], isTrue);
      expect(bootstrap.containsKey('featureFlags'), isFalse);
      expect(bootstrap.containsKey('featureFlagPayloads'), isFalse);
    });

    test('defaults isIdentifiedId to false and serializes it', () {
      final config = PostHogConfig('test_project_token')
        ..bootstrap = const PostHogBootstrapConfig(distinctId: 'anon-abc');

      final bootstrap = config.toMap()['bootstrap'] as Map<String, dynamic>;
      expect(bootstrap['distinctId'], equals('anon-abc'));
      expect(bootstrap['isIdentifiedId'], isFalse);
    });

    test('serializes feature flags and payloads without identity', () {
      final config = PostHogConfig('test_project_token')
        ..bootstrap = const PostHogBootstrapConfig(
          featureFlags: {'beta-ui': 'variant-a', 'legacy': true},
          featureFlagPayloads: {
            'beta-ui': {'color': 'blue'},
          },
        );

      final bootstrap = config.toMap()['bootstrap'] as Map<String, dynamic>;
      expect(bootstrap.containsKey('distinctId'), isFalse);
      expect(bootstrap['isIdentifiedId'], isFalse);
      expect(
        bootstrap['featureFlags'],
        equals({'beta-ui': 'variant-a', 'legacy': true}),
      );
      expect(
        bootstrap['featureFlagPayloads'],
        equals({
          'beta-ui': {'color': 'blue'},
        }),
      );
    });
  });

  group('PostHogPlatformView', () {
    testWidgets('defaults privacy to mask', (tester) async {
      const view = PostHogPlatformView(child: SizedBox());
      expect(view.privacy, PostHogPlatformViewPrivacy.mask);
    });

    testWidgets('keeps the requested capture privacy', (tester) async {
      const view = PostHogPlatformView(
        privacy: PostHogPlatformViewPrivacy.capture,
        child: SizedBox(),
      );
      expect(view.privacy, PostHogPlatformViewPrivacy.capture);
    });

    testWidgets('renders its child unchanged', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: PostHogPlatformView(child: Text('child')),
        ),
      );
      expect(find.text('child'), findsOneWidget);
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
        3,
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

      expect(
        fakePlatformInterface.getFeatureFlagResultCalls.last['sendEvent'],
        isTrue,
      );
    });

    test('passes sendEvent=false when specified', () async {
      fakePlatformInterface.featureFlagValues['test'] = true;

      await Posthog().getFeatureFlagResult('test', sendEvent: false);

      expect(
        fakePlatformInterface.getFeatureFlagResultCalls.last['sendEvent'],
        isFalse,
      );
    });
  });

  group('setPersonProperties', () {
    late PosthogFlutterPlatformFake fakePlatformInterface;

    setUp(() {
      fakePlatformInterface = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fakePlatformInterface;
    });

    test('passes userPropertiesToSet to platform interface', () async {
      await Posthog().setPersonProperties(
        userPropertiesToSet: {'name': 'John Doe', 'email': 'john@example.com'},
      );

      expect(fakePlatformInterface.setPersonPropertiesCalls.length, 1);
      expect(
        fakePlatformInterface
            .setPersonPropertiesCalls.last['userPropertiesToSet'],
        {'name': 'John Doe', 'email': 'john@example.com'},
      );
    });

    test('passes userPropertiesToSetOnce to platform interface', () async {
      await Posthog().setPersonProperties(
        userPropertiesToSetOnce: {'date_of_first_login': '2024-03-01'},
      );

      expect(fakePlatformInterface.setPersonPropertiesCalls.length, 1);
      expect(
        fakePlatformInterface
            .setPersonPropertiesCalls.last['userPropertiesToSetOnce'],
        {'date_of_first_login': '2024-03-01'},
      );
    });

    test('passes both property types to platform interface', () async {
      await Posthog().setPersonProperties(
        userPropertiesToSet: {'name': 'John Doe'},
        userPropertiesToSetOnce: {'created_at': '2024-03-01'},
      );

      expect(fakePlatformInterface.setPersonPropertiesCalls.length, 1);
      final call = fakePlatformInterface.setPersonPropertiesCalls.last;
      expect(call['userPropertiesToSet'], {'name': 'John Doe'});
      expect(call['userPropertiesToSetOnce'], {'created_at': '2024-03-01'});
    });

    test('can be called with no properties', () async {
      await Posthog().setPersonProperties();

      expect(fakePlatformInterface.setPersonPropertiesCalls.length, 1);
      final call = fakePlatformInterface.setPersonPropertiesCalls.last;
      expect(call['userPropertiesToSet'], isNull);
      expect(call['userPropertiesToSetOnce'], isNull);
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
          'PostHogFeatureFlagResult(key: my-flag, enabled: true, variant: test, payload: null)',
        ),
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
      final map = {'enabled': true, 'variant': null, 'payload': null};

      final result = PostHogFeatureFlagResult.fromMap(map, 'fallback-key');

      expect(result, isNotNull);
      expect(result!.key, equals('fallback-key'));
    });

    test('fromMap defaults enabled to false when not in map', () {
      final map = <String, dynamic>{'key': 'my-flag'};

      final result = PostHogFeatureFlagResult.fromMap(map, 'fallback');

      expect(result, isNotNull);
      expect(result!.enabled, isFalse);
    });
  });

  group('Posthog properties for flags', () {
    late PosthogFlutterPlatformFake fake;

    setUp(() async {
      fake = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fake;
      await Posthog().close();
    });

    test('setPersonPropertiesForFlags sets props and reloads by default',
        () async {
      await Posthog().setPersonPropertiesForFlags({'country': 'US'});

      expect(fake.setPersonPropertiesForFlagsCalls, [
        {'country': 'US'},
      ]);
      expect(fake.reloadFeatureFlagsCount, 1);
    });

    test(
        'setPersonPropertiesForFlags skips reload when reloadFeatureFlags=false',
        () async {
      await Posthog().setPersonPropertiesForFlags(
        {'country': 'US'},
        reloadFeatureFlags: false,
      );

      expect(fake.setPersonPropertiesForFlagsCalls.length, 1);
      expect(fake.reloadFeatureFlagsCount, 0);
    });

    test('setPersonPropertiesForFlags is a no-op for empty map', () async {
      await Posthog().setPersonPropertiesForFlags({});

      expect(fake.setPersonPropertiesForFlagsCalls, isEmpty);
      expect(fake.reloadFeatureFlagsCount, 0);
    });

    test('resetPersonPropertiesForFlags resets and reloads by default',
        () async {
      await Posthog().resetPersonPropertiesForFlags();

      expect(fake.resetPersonPropertiesForFlagsCount, 1);
      expect(fake.reloadFeatureFlagsCount, 1);
    });

    test('setGroupPropertiesForFlags passes groupType and reloads', () async {
      await Posthog().setGroupPropertiesForFlags(
        'organization',
        {'name': 'ACME'},
      );

      expect(fake.setGroupPropertiesForFlagsCalls, [
        {
          'groupType': 'organization',
          'groupProperties': {'name': 'ACME'},
        },
      ]);
      expect(fake.reloadFeatureFlagsCount, 1);
    });

    test('setGroupPropertiesForFlags is a no-op for empty map', () async {
      await Posthog().setGroupPropertiesForFlags('organization', {});

      expect(fake.setGroupPropertiesForFlagsCalls, isEmpty);
      expect(fake.reloadFeatureFlagsCount, 0);
    });

    test('resetGroupPropertiesForFlags forwards groupType and reloads',
        () async {
      await Posthog().resetGroupPropertiesForFlags(groupType: 'organization');

      expect(fake.resetGroupPropertiesForFlagsCalls, ['organization']);
      expect(fake.reloadFeatureFlagsCount, 1);
    });

    test('resetGroupPropertiesForFlags forwards null when groupType omitted',
        () async {
      await Posthog().resetGroupPropertiesForFlags(reloadFeatureFlags: false);

      expect(fake.resetGroupPropertiesForFlagsCalls, [null]);
      expect(fake.reloadFeatureFlagsCount, 0);
    });
  });

  group('Posthog addExceptionStep', () {
    late PosthogFlutterPlatformFake fake;

    setUp(() async {
      fake = PosthogFlutterPlatformFake();
      PosthogFlutterPlatformInterface.instance = fake;
      await Posthog().close();
    });

    test('forwards message and properties to the platform', () async {
      await Posthog().addExceptionStep(
        'User tapped Checkout',
        properties: {'screen': 'cart'},
      );

      expect(fake.addExceptionStepCalls, [
        {
          'message': 'User tapped Checkout',
          'properties': {'screen': 'cart'},
        },
      ]);
    });

    test('forwards message without properties', () async {
      await Posthog().addExceptionStep('Opened modal');

      expect(fake.addExceptionStepCalls, [
        {'message': 'Opened modal', 'properties': null},
      ]);
    });

    test('is a no-op for an empty message', () async {
      await Posthog().addExceptionStep('');

      expect(fake.addExceptionStepCalls, isEmpty);
    });

    test('is a no-op for a whitespace-only message', () async {
      await Posthog().addExceptionStep('   \t\n');

      expect(fake.addExceptionStepCalls, isEmpty);
    });

    test('is a no-op when exception steps are disabled', () async {
      final config = PostHogConfig('test_project_token')
        ..errorTrackingConfig.exceptionSteps.enabled = false;
      await Posthog().setup(config);

      await Posthog().addExceptionStep('User tapped Checkout');

      expect(fake.addExceptionStepCalls, isEmpty);
    });
  });

  group('PostHogExceptionStepsConfig', () {
    test('toMap serializes the native defaults', () {
      final config = PostHogConfig('test_project_token');

      expect(
        config.errorTrackingConfig.exceptionSteps.toMap(),
        {'enabled': true, 'maxBytes': 32768},
      );
    });

    test('toMap reflects overridden values', () {
      final config = PostHogConfig('test_project_token')
        ..errorTrackingConfig.exceptionSteps.enabled = false
        ..errorTrackingConfig.exceptionSteps.maxBytes = 1024;

      expect(
        config.errorTrackingConfig.exceptionSteps.toMap(),
        {'enabled': false, 'maxBytes': 1024},
      );
    });
  });
}
