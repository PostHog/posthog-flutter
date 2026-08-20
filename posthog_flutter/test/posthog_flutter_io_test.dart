import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/logs/posthog_log_severity.dart';
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

    test('setup sends projectToken and deprecated apiKey alias', () async {
      testConfig = PostHogConfig(' \n test_project_token\t ');
      await posthogFlutterIO.setup(testConfig);

      final call = log.firstWhere((c) => c.method == 'setup');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['projectToken'], equals('test_project_token'));
      expect(args['apiKey'], equals('test_project_token'));
    });

    test(
      'invokes callback when native sends onFeatureFlagsCallback event',
      () async {
        bool callbackInvoked = false;

        void testCallback() {
          callbackInvoked = true;
        }

        testConfig = PostHogConfig(
          'test_project_token',
          onFeatureFlags: testCallback,
        );
        await posthogFlutterIO.setup(testConfig);

        // Native sends empty map (iOS/Android behavior)
        final mockNativeArgs = <String, dynamic>{};

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgs),
          ),
          (ByteData? data) {},
        );

        expect(callbackInvoked, isTrue);
      },
    );

    test(
      'invokes callback when native sends onFeatureFlagsCallback with empty map (mobile behavior)',
      () async {
        bool callbackInvoked = false;

        void testCallback() {
          callbackInvoked = true;
        }

        testConfig = PostHogConfig(
          'test_project_token',
          onFeatureFlags: testCallback,
        );
        await posthogFlutterIO.setup(testConfig);

        // Simulate mobile sending an empty map
        final mockNativeArgs = <String, dynamic>{};

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('onFeatureFlagsCallback', mockNativeArgs),
          ),
          (ByteData? data) {},
        );

        expect(callbackInvoked, isTrue);
      },
    );

    test('invokes callback even with malformed native args', () async {
      bool callbackInvoked = false;

      void testCallback() {
        callbackInvoked = true;
      }

      testConfig =
          PostHogConfig('test_project_token', onFeatureFlags: testCallback);
      await posthogFlutterIO.setup(testConfig);

      // Simulate native sending malformed arguments - callback should still be invoked
      final mockNativeArgsMalformed = {
        'flags': 123, // Invalid type, but callback is void so it doesn't matter
      };

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('onFeatureFlagsCallback', mockNativeArgsMalformed),
        ),
        (ByteData? data) {},
      );

      expect(callbackInvoked, isTrue);
    });

    test('does not invoke callback when no callback is registered', () async {
      // Setup without callback
      testConfig = PostHogConfig('test_project_token');
      await posthogFlutterIO.setup(testConfig);

      // This should not throw - just silently do nothing
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('onFeatureFlagsCallback', {}),
        ),
        (ByteData? data) {},
      );

      // If we get here without exception, the test passes
      expect(true, isTrue);
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['eventName'], 'modified_event');
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['userProperties'], {'name': 'Modified Name'});
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['userPropertiesSetOnce'], {
        'last_logged_in_at': '2025-01-01',
      });
    });

    test('beforeSend can drop event by returning null', () async {
      testConfig =
          PostHogConfig('test_project_token', beforeSend: [(event) => null]);
      await posthogFlutterIO.setup(testConfig);

      await posthogFlutterIO.capture(eventName: 'dropped_event');

      final captureCalls = log.where((c) => c.method == 'capture');
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

      final captureCalls = log.where((c) => c.method == 'capture').toList();
      expect(captureCalls.length, 1);
      final args = Map<String, dynamic>.from(
        captureCalls.first.arguments as Map,
      );
      expect(args['eventName'], 'keep me');
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
      expect(log, isEmpty);
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['eventName'], 'original_first_second_third');
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

        final captureCall = log.firstWhere((c) => c.method == 'capture');
        final args = Map<String, dynamic>.from(captureCall.arguments as Map);
        expect(args['properties'], {'event_prop': 'value'});
        expect(args['userProperties'], {'developer_name': 'John'});
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

        final captureCall = log.firstWhere((c) => c.method == 'capture');
        final args = Map<String, dynamic>.from(captureCall.arguments as Map);
        expect(args['properties'], {'event_prop': 'value'});
        expect(args['userPropertiesSetOnce'], {'first_seen': '2025-01-01'});
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['properties'], {'event_prop': 'value'});
      expect(args['userProperties'], {
        'from_legacy': 'legacy_value',
        'from_direct': 'direct_value',
        'shared': 'direct',
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args.containsKey('userProperties'), isFalse);
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['eventName'], 'async_modified_event');
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

      final captureCalls = log.where((c) => c.method == 'capture');
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

      final captureCall = log.firstWhere((c) => c.method == 'capture');
      final args = Map<String, dynamic>.from(captureCall.arguments as Map);
      expect(args['eventName'], 'original_sync1_async1_sync2');
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

      expect(log, isEmpty);
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

        final captureCalls = log.where((c) => c.method == 'capture');
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

        final captureCalls = log.where((c) => c.method == 'capture').toList();
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
          event1Args['eventName'],
          event2Args['eventName'],
          event3Args['eventName'],
        ];
        expect(eventOrder, ['event_1', 'event_2', 'event_3']);
      },
    );

    test(
      'multiple events with async beforeSend are captured out of order when capture is NOT awaited',
      () async {
        testConfig = PostHogConfig(
          'test_project_token',
          beforeSend: [
            (event) async {
              // Add delay only for first event
              if (event.event == 'event_1') {
                await Future.delayed(const Duration(milliseconds: 100));
              }
              return event;
            },
          ],
        );
        await posthogFlutterIO.setup(testConfig);

        // Fire all events without awaiting - they run concurrently
        posthogFlutterIO.capture(eventName: 'event_1');
        posthogFlutterIO.capture(eventName: 'event_2');
        posthogFlutterIO.capture(eventName: 'event_3');

        // Wait for all to complete
        await Future.delayed(const Duration(milliseconds: 200));

        final captureCalls = log.where((c) => c.method == 'capture').toList();
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

        // Verify events were NOT captured in original order (event_1 should not be first due to delay)
        final eventOrder = [
          event1Args['eventName'],
          event2Args['eventName'],
          event3Args['eventName'],
        ];
        expect(eventOrder, isNot(['event_1', 'event_2', 'event_3']));
      },
    );
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
