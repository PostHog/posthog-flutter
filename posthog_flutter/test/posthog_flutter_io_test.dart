import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/feature_flag_result.dart';
import 'package:posthog_flutter/src/logs/posthog_log_severity.dart';
import 'package:posthog_flutter/src/feature_flags_loaded.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_event.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

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
      if (methodCall.method == 'buildEvent') {
        return nativeBuiltEvent(methodCall.arguments as Map);
      }
      if (methodCall.method == 'sendBuiltEvent') {
        return (methodCall.arguments as Map)['uuid'];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PosthogFlutterIO getFeatureFlagResult', () {
    for (final (enabled, variant, payload) in <(bool, String?, Object?)>[
      (true, null, null),
      (false, null, null),
      (true, 'variant-a', null),
      (true, null, {'discount': 10, 'message': 'Welcome!'}),
      (true, 'control', [1, 2, 3]),
    ]) {
      test('decodes enabled=$enabled variant=$variant payload=$payload',
          () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getFeatureFlagResult');
          expect(call.arguments, {'key': 'flag', 'sendEvent': false});
          return {
            'key': 'flag',
            'enabled': enabled,
            'variant': variant,
            'payload': payload
          };
        });
        final result = await posthogFlutterIO.getFeatureFlagResult(
            key: 'flag', sendFeatureFlagEvent: false);
        expect(result, isNotNull);
        expect(result!.key, 'flag');
        expect(result.enabled, enabled);
        expect(result.variant, variant);
        expect(result.payload, payload);
      });
    }
    test('preserves a missing native result', () async {
      expect(
          await posthogFlutterIO.getFeatureFlagResult(key: 'missing'), isNull);
      expect(log.single.method, 'getFeatureFlagResult');
      expect(log.single.arguments, {'key': 'missing'});
    });
  });

  group('PosthogFlutterIO feature events', () {
    test('captureFeatureView and captureFeatureInteraction call the native SDK',
        () async {
      await posthogFlutterIO.captureFeatureView(flag: 'a');
      await posthogFlutterIO.captureFeatureInteraction(
          flag: 'b', flagVariant: 'control');

      expect(log.map((call) => [call.method, call.arguments]), [
        [
          'captureFeatureView',
          {'flag': 'a'}
        ],
        [
          'captureFeatureInteraction',
          {'flag': 'b', 'flagVariant': 'control'}
        ],
      ]);
    });
  });

  group('PosthogFlutterIO exception events', () {
    test('passes AOT debug images and addresses through the native channel',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await posthogFlutterIO.captureException(
        error: StateError('sample failure'),
        stackTrace: StackTrace.fromString('''
build_id: 'b718850999efbed01ab80642060ddbf3'
isolate_dso_base: 7000000000
#0 abs 7000205218 _kDartIsolateSnapshotInstructions+0x20
'''),
      );

      final call = log.singleWhere((item) => item.method == 'captureException');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final properties = Map<String, dynamic>.from(args['properties'] as Map);
      final images = properties['\$debug_images'] as List;
      expect(images.single, {
        'debug_id': '098518b7-ef99-d0be-1ab8-0642060ddbf3',
        'image_addr': '0x7000000000',
        'type': 'elf',
      });
      final exception = (properties['\$exception_list'] as List).single as Map;
      final frames = (exception['stacktrace'] as Map)['frames'] as List;
      expect((frames.single as Map)['instruction_addr'], '0x7000205218');
    });
  });

  group('PosthogFlutterIO sendFeatureFlagEvent', () {
    for (final sendFeatureFlagEvent in [null, true, false]) {
      final expected = {
        'key': 'flag',
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      };

      test('getFeatureFlag sends $expected', () async {
        await posthogFlutterIO.getFeatureFlag(
            key: 'flag', sendFeatureFlagEvent: sendFeatureFlagEvent);
        expect(log.single.method, 'getFeatureFlag');
        expect(log.single.arguments, expected);
      });

      test('isFeatureEnabled sends $expected', () async {
        await posthogFlutterIO.isFeatureEnabled('flag',
            sendFeatureFlagEvent: sendFeatureFlagEvent);
        expect(log.single.method, 'isFeatureEnabled');
        expect(log.single.arguments, expected);
      });
    }
  });

  group('PosthogFlutterIO getAllFeatureFlags', () {
    test('decodes the native results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getAllFeatureFlags');
        return [
          {'key': 'on', 'enabled': true, 'variant': null, 'payload': null},
          {
            'key': 'multi',
            'enabled': true,
            'variant': 'control',
            'payload': {'discount': 10}
          },
        ];
      });

      final results = await posthogFlutterIO.getAllFeatureFlags();
      expect(results, [
        const PostHogFeatureFlagResult(key: 'on', enabled: true),
        const PostHogFeatureFlagResult(
            key: 'multi', enabled: true, variant: 'control'),
      ]);
      expect(results![1].payload, {'discount': 10});
    });

    test('preserves a missing native result', () async {
      expect(await posthogFlutterIO.getAllFeatureFlags(), isNull);
      expect(log.single.method, 'getAllFeatureFlags');
    });
  });

  group('PosthogFlutterIO onFeatureFlags via setup', () {
    test(
      'setup initializes method call handler and registers callback if provided',
      () async {
        bool callbackInvoked = false;
        void testCallback(PostHogFeatureFlagsLoaded _) {
          callbackInvoked = true;
        }

        testConfig = PostHogConfig(
          'test_project_token',
          onFeatureFlags: testCallback,
        );
        await posthogFlutterIO.setup(testConfig);

        // To verify handler is set, we trigger the callback from native side
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall('onFeatureFlagsCallback', {}),
          ),
          (ByteData? data) {},
        );
        expect(callbackInvoked, isTrue);
        expect(log.any((call) => call.method == 'setup'), isTrue);
      },
    );

    test('setup sends projectToken', () async {
      testConfig = PostHogConfig(' \n test_project_token\t ');
      await posthogFlutterIO.setup(testConfig);

      final call = log.firstWhere((c) => c.method == 'setup');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['projectToken'], equals('test_project_token'));
      expect(args.containsKey('apiKey'), isFalse);
    });

    test(
      'setup sends the Flutter version for native lifecycle events',
      skip: const String.fromEnvironment('FLUTTER_VERSION').isEmpty
          ? 'FLUTTER_VERSION is only defined on Flutter 3.32+'
          : null,
      () async {
        await posthogFlutterIO.setup(PostHogConfig('test_project_token'));

        final call = log.firstWhere((c) => c.method == 'setup');
        expect(
          (call.arguments as Map)['flutterVersion'],
          const String.fromEnvironment('FLUTTER_VERSION'),
        );
      },
    );

    test('passes the native flags to the callback', () async {
      final received = <PostHogFeatureFlagsLoaded>[];
      await posthogFlutterIO.setup(
          PostHogConfig('test_project_token', onFeatureFlags: received.add));

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall(
          'onFeatureFlagsCallback',
          {
            'variants': {'on': true, 'variant': 'test', 'off': false},
            'errorsLoading': true,
          },
        )),
        (ByteData? data) {},
      );

      expect(received.single.variants, {'on': true, 'variant': 'test'});
      expect(received.single.flags, ['on', 'variant']);
      expect(received.single.errorsLoading, isTrue);
    });

    test('passes empty flags to the callback for malformed native args',
        () async {
      final received = <PostHogFeatureFlagsLoaded>[];
      await posthogFlutterIO.setup(
          PostHogConfig('test_project_token', onFeatureFlags: received.add));

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('onFeatureFlagsCallback', {'variants': 123}),
        ),
        (ByteData? data) {},
      );

      expect(received.single.variants, isEmpty);
    });

    test('does not invoke callback when no callback is registered', () async {
      // Setup without callback
      testConfig = PostHogConfig('test_project_token');
      await posthogFlutterIO.setup(testConfig);

      ByteData? reply;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('onFeatureFlagsCallback', {}),
        ),
        (ByteData? data) => reply = data,
      );

      expect(reply, isNotNull);
      expect(channel.codec.decodeEnvelope(reply!), isNull);
    });
  });

  group('PosthogFlutterIO setPersonProperties', () {
    test('sends method channel call with userPropertiesToSet', () async {
      testConfig = PostHogConfig('test_project_token');
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.setPersonProperties(
        userPropertiesToSet: {'name': 'John Doe', 'email': 'john@example.com'},
      );

      final call = log.firstWhere((c) => c.method == 'setPersonProperties');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['userPropertiesToSet'], {
        'name': 'John Doe',
        'email': 'john@example.com',
      });
      expect(args.containsKey('userPropertiesToSetOnce'), isFalse);
    });

    test('sends method channel call with userPropertiesToSetOnce', () async {
      testConfig = PostHogConfig('test_project_token');
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.setPersonProperties(
        userPropertiesToSetOnce: {'date_of_first_login': '2024-03-01'},
      );

      final call = log.firstWhere((c) => c.method == 'setPersonProperties');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['userPropertiesToSetOnce'], {
        'date_of_first_login': '2024-03-01',
      });
      expect(args.containsKey('userPropertiesToSet'), isFalse);
    });

    test('sends method channel call with both property types', () async {
      testConfig = PostHogConfig('test_project_token');
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.setPersonProperties(
        userPropertiesToSet: {'name': 'John Doe'},
        userPropertiesToSetOnce: {'created_at': '2024-03-01'},
      );

      final call = log.firstWhere((c) => c.method == 'setPersonProperties');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['userPropertiesToSet'], {'name': 'John Doe'});
      expect(args['userPropertiesToSetOnce'], {'created_at': '2024-03-01'});
    });
  });

  group('PosthogFlutterIO properties for flags', () {
    setUp(() async {
      testConfig = PostHogConfig('test_project_token');
      await posthogFlutterIO.setup(testConfig);
    });

    test('setPersonPropertiesForFlags sends userProperties', () async {
      await posthogFlutterIO.setPersonPropertiesForFlags({
        'storefront_country': 'US',
        'superwall_demand_score': 88,
      });

      final call =
          log.firstWhere((c) => c.method == 'setPersonPropertiesForFlags');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['userProperties'], {
        'storefront_country': 'US',
        'superwall_demand_score': 88,
      });
    });

    test('resetPersonPropertiesForFlags sends method channel call', () async {
      await posthogFlutterIO.resetPersonPropertiesForFlags();

      expect(
        log.any((c) => c.method == 'resetPersonPropertiesForFlags'),
        isTrue,
      );
    });

    test('setCaptureNativeScreens sends the enabled flag', () async {
      await posthogFlutterIO.setCaptureNativeScreens(false);
      await posthogFlutterIO.setCaptureNativeScreens(true);

      final calls =
          log.where((c) => c.method == 'setCaptureNativeScreens').toList();
      expect(calls.map((c) => c.arguments), [
        {'enabled': false},
        {'enabled': true},
      ]);
    });

    test('setGroupPropertiesForFlags sends groupType and properties', () async {
      await posthogFlutterIO.setGroupPropertiesForFlags(
        'organization',
        {'name': 'ACME Corp', 'is_enterprise': true},
      );

      final call =
          log.firstWhere((c) => c.method == 'setGroupPropertiesForFlags');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['groupType'], 'organization');
      expect(args['groupProperties'], {
        'name': 'ACME Corp',
        'is_enterprise': true,
      });
    });

    test('resetGroupPropertiesForFlags includes groupType when provided',
        () async {
      await posthogFlutterIO.resetGroupPropertiesForFlags(
        groupType: 'organization',
      );

      final call =
          log.firstWhere((c) => c.method == 'resetGroupPropertiesForFlags');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['groupType'], 'organization');
    });

    test('resetGroupPropertiesForFlags omits groupType when null', () async {
      await posthogFlutterIO.resetGroupPropertiesForFlags();

      final call =
          log.firstWhere((c) => c.method == 'resetGroupPropertiesForFlags');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args.containsKey('groupType'), isFalse);
    });
  });

  group('PosthogFlutterIO event options', () {
    const options = <String, Object?>{
      'process_person_profile': false,
      'custom_key': 'kept',
      'unset_key': null,
    };
    const sent = {'process_person_profile': false, 'custom_key': 'kept'};

    Map<String, dynamic> argsOf(String method) => Map<String, dynamic>.from(
          log.singleWhere((c) => c.method == method).arguments as Map,
        );

    setUp(() async {
      await posthogFlutterIO.setup(PostHogConfig('test_project_token'));
    });

    final callsByMethod = <String, Future<void> Function(PosthogFlutterIO)>{
      'capture': (io) => io.capture(eventName: 'clicked', options: options),
      'screen': (io) => io.screen(screenName: 'Home', options: options),
      'captureException': (io) =>
          io.captureException(error: StateError('boom'), options: options),
      'identify': (io) => io.identify(userId: 'user-1', options: options),
      'setPersonProperties': (io) => io.setPersonProperties(
            userPropertiesToSet: {'plan': 'pro'},
            options: options,
          ),
      'alias': (io) => io.alias(alias: 'alias-1', options: options),
      'group': (io) =>
          io.group(groupType: 'company', groupKey: 'acme', options: options),
      'captureAi': (io) =>
          io.captureAi(eventName: r'$ai_generation', options: options),
    };

    for (final entry in callsByMethod.entries) {
      test('${entry.key} sends the options without unset keys', () async {
        await entry.value(posthogFlutterIO);
        expect(argsOf(entry.key)['options'], sent);
      });
    }

    test('calls without options send no options argument', () async {
      await posthogFlutterIO.capture(eventName: 'clicked');
      await posthogFlutterIO.alias(alias: 'alias-1', options: {'k': null});
      expect(argsOf('capture'), isNot(contains('options')));
      expect(argsOf('alias'), isNot(contains('options')));
    });

    test('captureAi sends the event and returns the native uuid', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return call.method == 'captureAi' ? 'uuid-1' : null;
      });

      final uuid = await posthogFlutterIO.captureAi(
        eventName: r'$ai_generation',
        properties: {r'$ai_model': 'gpt-4o'},
        userProperties: {'plan': 'pro'},
      );

      expect(uuid, 'uuid-1');
      expect(argsOf('captureAi'), {
        'eventName': r'$ai_generation',
        'properties': {r'$ai_model': 'gpt-4o'},
        'userProperties': {'plan': 'pro'},
      });
      expect(log.where((c) => c.method == 'capture'), isEmpty);
    });

    test('beforeSend sees and can change the options', () async {
      final seen = <Map<String, Object?>?>[];
      await posthogFlutterIO.setup(PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            seen.add({...?event.options});
            event.options = {...?event.options, 'product_tour_id': 'tour-1'}
              ..remove('custom_key');
            return event;
          },
        ],
      ));

      await posthogFlutterIO.captureAi(
          eventName: r'$ai_span', options: options);
      await posthogFlutterIO.screen(screenName: 'Home', options: options);

      expect(seen, [sent, sent]);
      const changed = {
        'process_person_profile': false,
        'product_tour_id': 'tour-1',
      };
      final sends = log.where((c) => c.method == 'sendBuiltEvent').toList();
      expect(sends.map((c) => (c.arguments as Map)['options']),
          [changed, changed]);
    });

    test('a screen renamed by beforeSend keeps its options', () async {
      await posthogFlutterIO.setup(PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            if (event.event == r'$screen') event.event = 'screen viewed';
            return event;
          },
        ],
      ));

      await posthogFlutterIO.screen(screenName: 'Home', options: options);

      expect(argsOf('sendBuiltEvent')['event'], 'screen viewed');
      expect(argsOf('sendBuiltEvent')['options'], sent);
    });

    test('captureAi dropped by beforeSend returns null', () async {
      await posthogFlutterIO.setup(PostHogConfig(
        'test_project_token',
        beforeSend: [(event) => null],
      ));

      expect(
        await posthogFlutterIO.captureAi(eventName: r'$ai_generation'),
        isNull,
      );
      expect(log.where((c) => c.method == 'sendBuiltEvent'), isEmpty);
    });
  });

  group('PosthogFlutterIO beforeSend callback', () {
    test(
      'capture sends event unchanged when no beforeSend registered',
      () async {
        testConfig = PostHogConfig('test_project_token');
        await posthogFlutterIO.setup(testConfig);

        await posthogFlutterIO.capture(
          eventName: 'test_event',
          properties: {'key': 'value'},
        );

        final captureCall = log.firstWhere((c) => c.method == 'capture');
        final args = Map<String, dynamic>.from(captureCall.arguments as Map);
        expect(args['eventName'], 'test_event');
        expect(args['properties'], {'key': 'value'});
      },
    );

    test('beforeSend can modify event name', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            event.event = 'modified_event';
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'original_event');

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['event'], 'modified_event');
    });

    test('beforeSend can modify properties', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            event.properties = {'modified': true};
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(
        eventName: 'test_event',
        properties: {'original': true},
      );

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['properties'], {'modified': true});
    });

    test('beforeSend can modify userProperties', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            event.userProperties = {'name': 'Modified Name'};
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(
        eventName: 'test_event',
        userProperties: {'name': 'Original Name'},
      );

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['properties'], {
        r'$set': {'name': 'Modified Name'}
      });
    });

    test('beforeSend can modify userPropertiesSetOnce', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            event.userPropertiesSetOnce = {'last_logged_in_at': '2025-01-01'};
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(
        eventName: 'test_event',
        userPropertiesSetOnce: {'last_logged_in_at': '2024-01-01'},
      );

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['properties'], {
        r'$set_once': {'last_logged_in_at': '2025-01-01'},
      });
    });

    test('beforeSend can drop event by returning null', () async {
      testConfig =
          PostHogConfig('test_project_token', beforeSend: [(event) => null]);
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'dropped_event');

      final captureCalls = log.where((c) => c.method == 'sendBuiltEvent');
      expect(captureCalls, isEmpty);
    });

    test('beforeSend can selectively drop events', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            if (event.event == 'drop me') return null;
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'drop me');
      await posthogFlutterIO.capture(eventName: 'keep me');

      final captureCalls =
          log.where((c) => c.method == 'sendBuiltEvent').toList();
      expect(captureCalls.length, 1);
      final args = Map<String, dynamic>.from(
        captureCalls.first.arguments as Map,
      );
      expect(args['event'], 'keep me');
    });

    test('beforeSend exception drops event and stops the chain', () async {
      final callOrder = <String>[];

      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            callOrder.add('transform');
            event.event = 'transformed_event';
            return event;
          },
          (event) {
            callOrder.add('throw');
            throw Exception('Hey I errored out');
          },
          (event) {
            callOrder.add('sentinel');
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);
      log.clear();

      await expectLater(
        posthogFlutterIO.capture(
          eventName: 'test_event',
          properties: {'key': 'value'},
        ),
        completes,
      );

      expect(callOrder, ['transform', 'throw']);
      expect(log.where((c) => c.method == 'sendBuiltEvent'), isEmpty);
    });

    test('multiple beforeSend callbacks are applied in order', () async {
      final callOrder = <int>[];

      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            callOrder.add(1);
            return PostHogEvent(
              event: '${event.event}_first',
              properties: event.properties,
              userProperties: event.userProperties,
              userPropertiesSetOnce: event.userPropertiesSetOnce,
            );
          },
          (event) {
            callOrder.add(2);
            event.event = '${event.event}_second';
            return event;
          },
          (event) {
            callOrder.add(3);
            event.event = '${event.event}_third';
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'original');

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['event'], 'original_first_second_third');
      expect(callOrder, [1, 2, 3]);
    });

    test(
      'beforeSend receives userProperties and userPropertiesSetOnce',
      () async {
        PostHogEvent? capturedEvent;

        testConfig = PostHogConfig(
          'test_project_token',
          beforeSend: [
            (event) {
              capturedEvent = event;
              return event;
            },
          ],
        );
        await posthogFlutterIO.setup(testConfig);

        await posthogFlutterIO.capture(
          eventName: 'test_event',
          properties: {'prop': 'value'},
          userProperties: {'user_prop': 'user_value'},
          userPropertiesSetOnce: {'set_once_prop': 'set_once_value'},
        );

        expect(capturedEvent, isNotNull);
        expect(capturedEvent!.event, 'test_event');
        expect(capturedEvent!.properties, {'prop': 'value'});
        expect(capturedEvent!.userProperties, {'user_prop': 'user_value'});
        expect(capturedEvent!.userPropertiesSetOnce, {
          'set_once_prop': 'set_once_value',
        });
      },
    );

    test(
      'beforeSend adds \$set to properties but it is extracted as userProperties',
      () async {
        testConfig = PostHogConfig(
          'test_project_token',
          beforeSend: [
            (event) {
              event.properties = {
                ...?event.properties,
                '\$set': {'developer_name': 'John'},
              };
              return event;
            },
          ],
        );
        await posthogFlutterIO.setup(testConfig);

        await posthogFlutterIO.capture(
          eventName: 'test_event',
          properties: {'event_prop': 'value'},
        );

        final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
        final args = Map<String, dynamic>.from(captureCall.arguments as Map);
        expect(args['properties'], {
          'event_prop': 'value',
          r'$set': {'developer_name': 'John'},
        });
      },
    );

    test(
      'beforeSend adds \$set_once to properties but it is extracted as userPropertiesSetOnce',
      () async {
        testConfig = PostHogConfig(
          'test_project_token',
          beforeSend: [
            (event) {
              event.properties = {
                ...?event.properties,
                '\$set_once': {'first_seen': '2025-01-01'},
              };
              return event;
            },
          ],
        );
        await posthogFlutterIO.setup(testConfig);

        await posthogFlutterIO.capture(
          eventName: 'test_event',
          properties: {'event_prop': 'value'},
        );

        final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
        final args = Map<String, dynamic>.from(captureCall.arguments as Map);
        expect(args['properties'], {
          'event_prop': 'value',
          r'$set_once': {'first_seen': '2025-01-01'},
        });
      },
    );

    test('beforeSend legacy \$set merges with direct userProperties', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            event.properties = {
              ...?event.properties,
              '\$set': {'from_legacy': 'legacy_value', 'shared': 'legacy'},
            };
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(
        eventName: 'test_event',
        properties: {'event_prop': 'value'},
        userProperties: {'from_direct': 'direct_value', 'shared': 'direct'},
      );

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['properties'], {
        'event_prop': 'value',
        r'$set': {
          'from_legacy': 'legacy_value',
          'from_direct': 'direct_value',
          'shared': 'direct',
        },
      });
    });

    test('beforeSend can clear userProperties by setting to null', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            event.userProperties = null;
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(
        eventName: 'test_event',
        userProperties: {'name': 'John'},
      );

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['properties'], isNot(contains(r'$set')));
    });

    test('async beforeSend can modify event', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) async {
            await Future.delayed(const Duration(milliseconds: 10));
            event.event = 'async_modified_event';
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'original_event');

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['event'], 'async_modified_event');
    });

    test('async beforeSend can drop event by returning null', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) async {
            await Future.delayed(const Duration(milliseconds: 100));
            return null;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'dropped_event');

      final captureCalls = log.where((c) => c.method == 'sendBuiltEvent');
      expect(captureCalls, isEmpty);
    });

    test('mixed sync and async beforeSend callbacks work correctly', () async {
      final callOrder = <String>[];

      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) {
            callOrder.add('sync1');
            event.event = '${event.event}_sync1';
            return event;
          },
          (event) async {
            await Future.delayed(const Duration(milliseconds: 100));
            callOrder.add('async1');
            event.event = '${event.event}_async1';
            return event;
          },
          (event) {
            callOrder.add('sync2');
            event.event = '${event.event}_sync2';
            return event;
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'original');

      final captureCall = log.firstWhere((c) => c.method == 'sendBuiltEvent');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['event'], 'original_sync1_async1_sync2');
      expect(callOrder, ['sync1', 'async1', 'sync2']);
    });

    test('async beforeSend exception drops event without throwing', () async {
      testConfig = PostHogConfig(
        'test_project_token',
        beforeSend: [
          (event) async {
            await Future<void>.delayed(Duration.zero);
            throw Exception('Async error');
          },
        ],
      );
      await posthogFlutterIO.setup(testConfig);
      log.clear();

      await expectLater(
        posthogFlutterIO.capture(
          eventName: 'test_event',
          properties: {'key': 'value'},
        ),
        completes,
      );

      expect(log.where((c) => c.method == 'sendBuiltEvent'), isEmpty);
    });

    test(
      'async beforeSend drops event and stops chain when returning null',
      () async {
        final callOrder = <int>[];

        testConfig = PostHogConfig(
          'test_project_token',
          beforeSend: [
            (event) async {
              callOrder.add(1);
              await Future.delayed(const Duration(milliseconds: 100));
              return null; // Drop event
            },
            (event) {
              callOrder.add(2); // Should not be called
              return event;
            },
          ],
        );
        await posthogFlutterIO.setup(testConfig);

        await posthogFlutterIO.capture(eventName: 'test_event');

        final captureCalls = log.where((c) => c.method == 'sendBuiltEvent');
        expect(captureCalls, isEmpty);
        expect(callOrder, [1]); // Only first callback should have been called
      },
    );

    test(
      'multiple events with async beforeSend are captured in order when capture is awaited',
      () async {
        testConfig = PostHogConfig(
          'test_project_token',
          beforeSend: [
            (event) async {
              // Add delay only for second event
              if (event.event == 'event_2') {
                await Future.delayed(const Duration(milliseconds: 500));
              }
              return event;
            },
          ],
        );
        await posthogFlutterIO.setup(testConfig);

        await posthogFlutterIO.capture(eventName: 'event_1');
        await posthogFlutterIO.capture(eventName: 'event_2');
        await posthogFlutterIO.capture(eventName: 'event_3');

        final captureCalls =
            log.where((c) => c.method == 'sendBuiltEvent').toList();
        expect(captureCalls.length, 3);

        final event1Args = Map<String, dynamic>.from(
          captureCalls[0].arguments as Map,
        );
        final event2Args = Map<String, dynamic>.from(
          captureCalls[1].arguments as Map,
        );
        final event3Args = Map<String, dynamic>.from(
          captureCalls[2].arguments as Map,
        );

        final eventOrder = [
          event1Args['event'],
          event2Args['event'],
          event3Args['event'],
        ];
        expect(eventOrder, ['event_1', 'event_2', 'event_3']);
      },
    );

    test(
      'multiple events with async beforeSend are captured out of order when capture is NOT awaited',
      () async {
        final releaseFirst = Completer<void>();
        testConfig = PostHogConfig(
          'test_project_token',
          beforeSend: [
            (event) async {
              if (event.event == 'event_1') {
                await releaseFirst.future;
              }
              return event;
            },
          ],
        );
        await posthogFlutterIO.setup(testConfig);

        final first = posthogFlutterIO.capture(eventName: 'event_1');
        await posthogFlutterIO.capture(eventName: 'event_2');
        await posthogFlutterIO.capture(eventName: 'event_3');
        expect(log.where((c) => c.method == 'sendBuiltEvent'), hasLength(2));
        releaseFirst.complete();
        await first;

        final captureCalls =
            log.where((c) => c.method == 'sendBuiltEvent').toList();
        expect(captureCalls.length, 3);

        final event1Args = Map<String, dynamic>.from(
          captureCalls[0].arguments as Map,
        );
        final event2Args = Map<String, dynamic>.from(
          captureCalls[1].arguments as Map,
        );
        final event3Args = Map<String, dynamic>.from(
          captureCalls[2].arguments as Map,
        );

        final eventOrder = [
          event1Args['event'],
          event2Args['event'],
          event3Args['event'],
        ];
        expect(eventOrder, ['event_2', 'event_3', 'event_1']);
      },
    );
  });

  group('PosthogFlutterIO beforeSend on the native-built event', () {
    Map<String, dynamic> argsOf(String method) => Map<String, dynamic>.from(
          log.singleWhere((c) => c.method == method).arguments as Map,
        );

    Future<void> setUpWith(BeforeSendCallback callback) => posthogFlutterIO
        .setup(PostHogConfig('test_project_token', beforeSend: [callback]));

    test('without callbacks an event takes one native call', () async {
      await posthogFlutterIO.setup(PostHogConfig('test_project_token'));
      log.clear();

      await posthogFlutterIO.capture(eventName: 'clicked');

      expect(log.map((c) => c.method), ['capture']);
    });

    test('callbacks see what the native SDK added', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        if (call.method != 'buildEvent') return null;
        return {
          ...nativeBuiltEvent(call.arguments as Map),
          'properties': {
            r'$lib': 'posthog-flutter',
            'plan': 'pro',
            r'$set': {'name': 'Ada'},
          },
        };
      });
      PostHogEvent? seen;
      await setUpWith((event) => seen = event);

      await posthogFlutterIO.capture(eventName: 'clicked');

      expect(seen!.uuid, 'built-uuid');
      expect(seen!.distinctId, 'user-1');
      expect(seen!.timestamp, DateTime.utc(2026));
      expect(seen!.properties, {r'$lib': 'posthog-flutter', 'plan': 'pro'});
      expect(seen!.userProperties, {'name': 'Ada'});
    });

    test('sends what the callbacks return with the built uuid', () async {
      await setUpWith((event) => PostHogEvent(
            event: 'renamed',
            properties: {'a': 1},
            distinctId: 'user-2',
            timestamp: DateTime.utc(2025),
          ));

      await posthogFlutterIO.capture(eventName: 'clicked');

      expect(argsOf('sendBuiltEvent'), {
        'event': 'renamed',
        'properties': {'a': 1},
        'distinctId': 'user-2',
        'timestamp': DateTime.utc(2025).millisecondsSinceEpoch,
        'options': <String, Object?>{},
        'uuid': 'built-uuid',
        'ai': false,
      });
    });

    test('captureAi builds and sends on the AI lane', () async {
      await setUpWith((event) => event);

      final uuid =
          await posthogFlutterIO.captureAi(eventName: r'$ai_generation');

      expect(uuid, 'built-uuid');
      expect(argsOf('buildEvent')['ai'], isTrue);
      expect(argsOf('sendBuiltEvent')['ai'], isTrue);
    });

    test('screen builds a \$screen event with its name', () async {
      PostHogEvent? seen;
      await setUpWith((event) => seen = event);

      await posthogFlutterIO.screen(screenName: 'Home', properties: {'a': 1});

      expect(argsOf('buildEvent'), {
        'eventName': r'$screen',
        'properties': {'a': 1, r'$screen_name': 'Home'},
        'ai': false,
      });
      expect(seen!.event, r'$screen');
      expect(seen!.properties, {'a': 1, r'$screen_name': 'Home'});
    });

    test('captureException builds with its own timestamp', () async {
      await setUpWith((event) => event);

      await posthogFlutterIO.captureException(error: StateError('boom'));

      expect(argsOf('buildEvent')['eventName'], r'$exception');
      expect(argsOf('buildEvent')['timestamp'], isA<int>());
    });

    test('a dropped event is discarded, not sent', () async {
      await setUpWith((event) => null);

      await posthogFlutterIO.capture(eventName: 'clicked');

      expect(argsOf('discardBuiltEvent'), {'uuid': 'built-uuid'});
      expect(log.where((c) => c.method == 'sendBuiltEvent'), isEmpty);
    });

    test('an event the native SDK skips never reaches the callbacks', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return null;
      });
      var called = false;
      await setUpWith((event) {
        called = true;
        return event;
      });

      await posthogFlutterIO.capture(eventName: 'clicked');

      expect(called, isFalse);
      expect(log.where((c) => c.method == 'sendBuiltEvent'), isEmpty);
    });
  });

  group('PosthogFlutterIO captureLog', () {
    test('sends body, lowercase level name, and attributes', () async {
      await posthogFlutterIO.captureLog(
        body: 'checkout completed',
        level: PostHogLogSeverity.warn,
        attributes: {'order_id': 'ord_789'},
      );

      final call = log.firstWhere((c) => c.method == 'captureLog');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['body'], 'checkout completed');
      expect(args['level'], 'warn');
      expect(args['attributes'], {'order_id': 'ord_789'});
    });

    test('omits attributes when none provided', () async {
      await posthogFlutterIO.captureLog(body: 'hello');

      final call = log.firstWhere((c) => c.method == 'captureLog');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['level'], 'info');
      expect(args.containsKey('attributes'), isFalse);
    });

    const severityWireNames = {
      PostHogLogSeverity.trace: 'trace',
      PostHogLogSeverity.debug: 'debug',
      PostHogLogSeverity.info: 'info',
      PostHogLogSeverity.warn: 'warn',
      PostHogLogSeverity.error: 'error',
      PostHogLogSeverity.fatal: 'fatal',
    };
    severityWireNames.forEach((severity, wireName) {
      test('serializes ${severity.name} as "$wireName" on the wire', () async {
        await posthogFlutterIO.captureLog(body: 'x', level: severity);

        final call = log.firstWhere((c) => c.method == 'captureLog');
        final args = Map<String, dynamic>.from(call.arguments as Map);
        expect(args['level'], wireName);
      });
    });

    test('normalizes unsupported attribute values for the channel', () async {
      await posthogFlutterIO.captureLog(
        body: 'event',
        attributes: {'at': DateTime(2024, 3, 1)},
      );

      final call = log.firstWhere((c) => c.method == 'captureLog');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final attributes = Map<String, dynamic>.from(args['attributes'] as Map);
      // DateTime is not a StandardMessageCodec type; it is stringified.
      expect(attributes['at'], isA<String>());
    });

    test('sends trace fields when provided', () async {
      await posthogFlutterIO.captureLog(
        body: 'event',
        traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
        spanId: '00f067aa0ba902b7',
        traceFlags: 1,
      );

      final call = log.firstWhere((c) => c.method == 'captureLog');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['traceId'], '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(args['spanId'], '00f067aa0ba902b7');
      expect(args['traceFlags'], 1);
    });

    test('emits an explicit traceFlags of 0 but omits trace fields when null',
        () async {
      await posthogFlutterIO.captureLog(body: 'event', traceFlags: 0);

      final call = log.firstWhere((c) => c.method == 'captureLog');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['traceFlags'], 0);
      expect(args.containsKey('traceId'), isFalse);
      expect(args.containsKey('spanId'), isFalse);
    });
  });

  group('PosthogFlutterIO calls made while an event is in flight', () {
    List<String> sentAfterSetup() =>
        log.map((c) => c.method).where((m) => m != 'setup').toList();

    for (final slow in [false, true]) {
      test(
          'reach native after events captured before them '
          '(${slow ? 'async' : 'no'} beforeSend)', () async {
        await posthogFlutterIO
            .setup(PostHogConfig('test_project_token', beforeSend: [
          if (slow)
            (event) async {
              await Future<void>.delayed(Duration.zero);
              return event;
            },
        ]));

        final sent = [
          posthogFlutterIO.capture(eventName: 'checkout'),
          posthogFlutterIO.screen(screenName: 'Cart'),
          posthogFlutterIO.captureException(error: StateError('boom')),
        ];
        await posthogFlutterIO.reset();
        await posthogFlutterIO.identify(userId: 'new-user');
        await posthogFlutterIO.register('plan', 'pro');
        await Future.wait(sent);

        expect(sentAfterSetup(), [
          if (slow) ...[
            for (var i = 0; i < 3; i++) ...['buildEvent', 'sendBuiltEvent'],
          ] else ...[
            'capture',
            'screen',
            'captureException'
          ],
          'reset',
          'identify',
          'register',
        ]);
      });
    }

    test('an event keeps the callbacks set when it was captured', () async {
      await posthogFlutterIO.setup(
          PostHogConfig('test_project_token', beforeSend: [(event) => null]));
      log.clear();

      final sent = posthogFlutterIO.capture(eventName: 'checkout');
      await posthogFlutterIO.setup(PostHogConfig('test_project_token'));
      await sent;

      expect(log.map((c) => c.method),
          ['buildEvent', 'discardBuiltEvent', 'setup']);
    });

    final lifecycleCalls = <String, Future<void> Function()>{
      'disable': () => posthogFlutterIO.optOut(),
      'close': () => posthogFlutterIO.close(),
      'setup': () =>
          posthogFlutterIO.setup(PostHogConfig('test_project_token')),
    };
    lifecycleCalls.forEach((method, call) {
      test('$method waits for an event between its build and send', () async {
        await posthogFlutterIO.setup(PostHogConfig('test_project_token',
            beforeSend: [(event) => event]));
        log.clear();

        final sent = posthogFlutterIO.capture(eventName: 'checkout');
        await call();
        await sent;

        expect(
            log.map((c) => c.method), ['buildEvent', 'sendBuiltEvent', method]);
      });
    });
  });

  group('PosthogFlutterIO addExceptionStep', () {
    test('sends message and normalized properties', () async {
      await posthogFlutterIO.addExceptionStep(
        'User tapped Checkout',
        properties: {'screen': 'cart', 'at': DateTime(2024, 3, 1)},
      );

      final call = log.firstWhere((c) => c.method == 'addExceptionStep');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['message'], 'User tapped Checkout');
      final properties = Map<String, dynamic>.from(args['properties'] as Map);
      expect(properties['screen'], 'cart');
      // DateTime is not a StandardMessageCodec type; it is stringified.
      expect(properties['at'], isA<String>());
    });

    test('omits properties when none provided', () async {
      await posthogFlutterIO.addExceptionStep('Opened modal');

      final call = log.firstWhere((c) => c.method == 'addExceptionStep');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['message'], 'Opened modal');
      expect(args.containsKey('properties'), isFalse);
    });
  });

  group('onNativeOcclusionChanged', () {
    Future<void> pushOcclusion(Map<String, Object?> arguments) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('onNativeOcclusionChanged', arguments),
        ),
        (ByteData? data) {},
      );
    }

    setUp(() async {
      testConfig = PostHogConfig('test_project_token');
      await posthogFlutterIO.setup(testConfig);
      PostHogInternalEvents.nativeOcclusionActive = false;
      PostHogInternalEvents.nativeOcclusionEpisode = 0;
      PostHogInternalEvents.nativeBridgeFailed = false;
      PostHogInternalEvents.nativeOcclusionEvent.value = 0;
    });

    test('maps arguments into the occlusion state and notifies', () async {
      await pushOcclusion(
        {'occluded': true, 'episode': 7, 'bridgeFailed': true},
      );

      expect(PostHogInternalEvents.nativeOcclusionActive, isTrue);
      expect(PostHogInternalEvents.nativeOcclusionEpisode, 7);
      expect(PostHogInternalEvents.nativeBridgeFailed, isTrue);
      expect(PostHogInternalEvents.nativeOcclusionEvent.value, 1);
    });

    test('missing arguments reset to not-occluded episode 0', () async {
      await pushOcclusion(
        {'occluded': true, 'episode': 7, 'bridgeFailed': true},
      );
      await pushOcclusion(<String, Object?>{});

      expect(PostHogInternalEvents.nativeOcclusionActive, isFalse);
      expect(PostHogInternalEvents.nativeOcclusionEpisode, 0);
      expect(PostHogInternalEvents.nativeBridgeFailed, isFalse);
      expect(PostHogInternalEvents.nativeOcclusionEvent.value, 2);
    });

    test('an unchanged payload still notifies listeners', () async {
      final payload = {'occluded': true, 'episode': 3, 'bridgeFailed': false};
      await pushOcclusion(payload);
      await pushOcclusion(payload);

      expect(PostHogInternalEvents.nativeOcclusionEvent.value, 2);
    });
  });

  group('PosthogFlutterIO push notifications', () {
    Map<String, Object?> argsOf(String method) => Map<String, Object?>.from(
          log.firstWhere((c) => c.method == method).arguments as Map,
        );

    test('registerPushNotificationToken sends deviceToken and appId', () async {
      await posthogFlutterIO.registerPushNotificationToken(
        'token-abc',
        appId: 'com.example.app',
      );

      expect(argsOf('registerPushNotificationToken'), {
        'deviceToken': 'token-abc',
        'appId': 'com.example.app',
      });
    });

    test('registerPushNotificationToken omits appId when null', () async {
      await posthogFlutterIO.registerPushNotificationToken('token-abc');

      // Each native side derives its own app id, so the key must be absent
      // rather than present-and-null.
      expect(
        argsOf('registerPushNotificationToken'),
        {'deviceToken': 'token-abc'},
      );
    });

    test('unregisterPushNotificationToken sends no arguments', () async {
      await posthogFlutterIO.unregisterPushNotificationToken();

      final call =
          log.firstWhere((c) => c.method == 'unregisterPushNotificationToken');
      expect(call.arguments, isNull);
    });

    test('capturePushNotificationOpened forwards every field', () async {
      await posthogFlutterIO.capturePushNotificationOpened(
        title: 'Title',
        subtitle: 'Subtitle',
        body: 'Body',
        payload: {'posthog': '{"campaign_id":"x"}'},
        action: 'reply',
      );

      expect(argsOf('capturePushNotificationOpened'), {
        'title': 'Title',
        'subtitle': 'Subtitle',
        'body': 'Body',
        'payload': {'posthog': '{"campaign_id":"x"}'},
        'action': 'reply',
      });
    });

    test('capturePushNotificationOpened omits null fields', () async {
      await posthogFlutterIO.capturePushNotificationOpened(body: 'Body');

      expect(argsOf('capturePushNotificationOpened'), {'body': 'Body'});
    });

    test('capturePushNotificationOpened preserves empty strings', () async {
      // The native SDKs decide what to drop; the bridge must not pre-filter or
      // an empty title would look like an absent one.
      await posthogFlutterIO.capturePushNotificationOpened(title: '');

      expect(argsOf('capturePushNotificationOpened'), {'title': ''});
    });

    Future<Object?> mintIdentityToken() async {
      Object? reply;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('pushIdentityProvider', {
            'distinctId': 'user-1',
            'appId': 'com.example.app',
          }),
        ),
        (ByteData? data) {
          reply = data == null ? null : channel.codec.decodeEnvelope(data);
        },
      );
      return reply;
    }

    test('pushIdentityProvider replies with the minted token', () async {
      String? seenDistinctId;
      String? seenAppId;

      testConfig = PostHogConfig('test_project_token')
        ..pushIdentityProvider = (distinctId, appId) async {
          seenDistinctId = distinctId;
          seenAppId = appId;
          return 'minted-token';
        };
      await posthogFlutterIO.setup(testConfig);

      expect(await mintIdentityToken(), 'minted-token');
      expect(seenDistinctId, 'user-1');
      expect(seenAppId, 'com.example.app');
    });

    test('setup flags whether a provider is installed', () async {
      await posthogFlutterIO.setup(PostHogConfig('test_project_token'));
      expect(argsOf('setup')['pushIdentityProviderEnabled'], isFalse);

      log.clear();
      await posthogFlutterIO.setup(
        PostHogConfig('test_project_token')
          ..pushIdentityProvider = (_, __) async => 'tok',
      );
      expect(argsOf('setup')['pushIdentityProviderEnabled'], isTrue);
    });

    test('a throwing provider degrades to a null token', () async {
      testConfig = PostHogConfig('test_project_token')
        ..pushIdentityProvider = (_, __) async => throw StateError('backend');
      await posthogFlutterIO.setup(testConfig);

      // Native falls back to an unauthenticated request; it must never see the
      // exception.
      expect(await mintIdentityToken(), isNull);
    });

    test('no provider configured replies null', () async {
      await posthogFlutterIO.setup(PostHogConfig('test_project_token'));

      expect(await mintIdentityToken(), isNull);
    });
  });
}

/// What the native `buildEvent` handler returns for [args], without adding
/// SDK properties.
Map<String, Object?> nativeBuiltEvent(Map args, {String uuid = 'built-uuid'}) {
  return {
    'event': args['eventName'],
    'uuid': uuid,
    'distinctId': 'user-1',
    'timestamp': args['timestamp'] ?? 1767225600000,
    'properties': {
      ...?(args['properties'] as Map?),
      if (args['userProperties'] != null) r'$set': args['userProperties'],
      if (args['userPropertiesSetOnce'] != null)
        r'$set_once': args['userPropertiesSetOnce'],
    },
    'options': args['options'] ?? <String, Object?>{},
  };
}
