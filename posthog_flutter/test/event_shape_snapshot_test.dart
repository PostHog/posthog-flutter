import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:stack_trace/stack_trace.dart';

const _updateSnapshots = bool.fromEnvironment('UPDATE_EVENT_SHAPE_SNAPSHOTS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
    await Posthog().close();
    calls.clear();
  });

  tearDown(() async {
    await Posthog().close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('snapshots the Flutter-owned setup request parameters', () async {
    final config = PostHogConfig('snapshot_project_token')
      ..host = 'https://eu.i.posthog.com'
      ..flushAt = 12
      ..maxQueueSize = 800
      ..maxBatchSize = 25
      ..flushInterval = const Duration(seconds: 15)
      ..sendFeatureFlagEvents = false
      ..preloadFeatureFlags = false
      ..captureApplicationLifecycleEvents = false
      ..personProfiles = PostHogPersonProfiles.always
      ..sessionReplay = true
      ..capturePushNotificationSubscriptions = false
      ..capturePushNotificationOpened = false
      ..bootstrap = const PostHogBootstrapConfig(
        distinctId: 'snapshot-user',
        isIdentifiedId: true,
        featureFlags: {'checkout': 'variant-a'},
        featureFlagPayloads: {
          'checkout': {'color': 'blue'},
        },
      );
    config.sessionReplayConfig
      ..maskAllImages = false
      ..sampleRate = 0.25;
    config.errorTrackingConfig
      ..inAppIncludes.add('package:snapshot_app')
      ..captureFlutterErrors = true;
    config.logsConfig
      ..serviceName = 'checkout-app'
      ..serviceVersion = '1.2.3'
      ..environment = 'test'
      ..resourceAttributes = {'region': 'eu'}
      ..flushAt = 10;

    await Posthog().setup(config);

    await _expectSnapshot('setup_request.json', calls);
  });

  test('snapshots event and identity channel shapes', () async {
    final config = PostHogConfig(
      'snapshot_project_token',
      beforeSend: [
        (event) {
          event.properties = {
            ...?event.properties,
            'snapshot_before_send': 'event',
          };
          return event;
        },
      ],
    );
    await Posthog().setup(config);
    calls.clear();

    await Posthog().screen(
      screenName: 'Checkout',
      properties: {
        'cart_size': 3,
        'route': {'source': 'email', 'coupon': null},
      },
    );
    await Posthog().capture(
      eventName: 'order completed',
      properties: {
        'order_id': 'ord_123',
        'total': 42.5,
        'items': [
          {'sku': 'sku_1', 'quantity': 2, 'note': null},
        ],
        'placed_at': DateTime.utc(2024, 3, 1, 12, 30),
        r'$set': {'plan': 'legacy', 'legacy_only': true},
        r'$set_once': {'first_checkout_at': '2024-03-01'},
      },
      userProperties: {'plan': 'pro', 'email_verified': true},
      userPropertiesSetOnce: {'signup_source': 'invite'},
    );
    await Posthog().identify(
      userId: 'user_123',
      userProperties: {
        'email': 'person@example.com',
        'profile': {'role': 'admin', 'nickname': null},
      },
      userPropertiesSetOnce: {'created_at': DateTime.utc(2024, 1, 1)},
    );
    await Posthog().setPersonProperties(
      userPropertiesToSet: {'plan': 'enterprise'},
      userPropertiesToSetOnce: {'first_team': 'growth'},
    );
    await Posthog().alias(alias: 'legacy_user_456');
    await Posthog().group(
      groupType: 'company',
      groupKey: 'posthog',
      groupProperties: {'industry': 'analytics', 'employees': 100},
    );
    await Posthog().setPersonPropertiesForFlags({
      'plan': 'enterprise',
      'seats': 25,
    }, reloadFeatureFlags: false);
    await Posthog().setGroupPropertiesForFlags(
        'company',
        {
          'region': 'eu',
          'employees': 100,
        },
        reloadFeatureFlags: false);

    await _expectSnapshot('event_channel_shapes.json', calls);
  });

  test('snapshots applicable Flutter-built special event parameters', () async {
    final config = PostHogConfig(
      'snapshot_project_token',
      beforeSend: [
        (event) {
          event.properties = {
            ...?event.properties,
            'snapshot_before_send': 'event',
          };
          return event;
        },
      ],
    );
    config.logsConfig.beforeSend = [
      (record) {
        record.attributes = {
          ...?record.attributes,
          'snapshot_before_send': 'log',
        };
        return record;
      },
    ];
    await Posthog().setup(config);
    calls.clear();

    await Posthog().captureLog(
      body: 'checkout completed',
      level: PostHogLogSeverity.warn,
      attributes: {
        'order_id': 'ord_123',
        'attempted_at': DateTime.utc(2024, 3, 1, 12, 30),
      },
      traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
      spanId: '00f067aa0ba902b7',
      traceFlags: 0,
    );
    await Posthog().captureException(
      error: StateError('checkout failed'),
      stackTrace: Chain.parse(
        '#0      CheckoutService.submit '
        '(package:snapshot_app/checkout.dart:42:7)\n'
        '#1      main (package:snapshot_app/main.dart:10:3)',
      ),
      properties: {
        'order_id': 'ord_123',
        'attempted_at': DateTime.utc(2024, 3, 1, 12, 30),
      },
    );
    await Posthog().captureRunZonedGuardedError(
      error: ArgumentError('zoned checkout failure'),
      stackTrace: Chain.parse(
        '#0      CheckoutZone.run '
        '(package:snapshot_app/zone.dart:21:5)\n'
        '#1      main (package:snapshot_app/main.dart:12:3)',
      ),
      properties: {'zone': 'checkout'},
    );
    await Posthog().addExceptionStep(
      'User tapped Checkout',
      properties: {'screen': 'cart', 'item_count': 3},
    );
    await Posthog().capturePushNotificationOpened(
      title: 'Order ready',
      subtitle: 'Pickup available',
      body: 'Tap to view order ord_123',
      payload: {
        'posthog': {'campaign_id': 'campaign_123', 'delivery': null},
      },
      action: 'view_order',
    );

    final normalizedCalls = calls.map((call) {
      if (call.method != 'captureException') {
        return call;
      }

      final arguments = Map<String, Object?>.from(call.arguments as Map);
      expect(arguments['timestamp'], isA<int>());
      arguments['timestamp'] = '<timestamp-ms>';

      final properties = Map<String, Object?>.from(
        arguments['properties'] as Map,
      );
      final exceptionList = List<Object?>.from(
        properties[r'$exception_list'] as List,
      );
      final exception = Map<String, Object?>.from(exceptionList.single! as Map);
      expect(exception['thread_id'], isA<int>());
      exception['thread_id'] = '<thread-id>';
      exceptionList[0] = exception;
      properties[r'$exception_list'] = exceptionList;
      arguments['properties'] = properties;

      return MethodCall(call.method, arguments);
    }).toList();

    await _expectSnapshot('special_event_channel_shapes.json', normalizedCalls);
  });
}

Future<void> _expectSnapshot(String name, List<MethodCall> calls) async {
  final snapshotFile = File('test/snapshots/$name');
  final actual = calls
      .map(
        (call) => <String, Object?>{
          'method': call.method,
          'arguments': call.arguments,
        },
      )
      .toList();
  final formatted = const JsonEncoder.withIndent('  ').convert(actual);

  if (_updateSnapshots) {
    await snapshotFile.parent.create(recursive: true);
    await snapshotFile.writeAsString('$formatted\n');
  }

  expect(
    '$formatted\n',
    await snapshotFile.readAsString(),
    reason: 'Update this explicit fixture only after reviewing the shape diff. '
        'Run with --dart-define=UPDATE_EVENT_SHAPE_SNAPSHOTS=true to accept it.',
  );
}
