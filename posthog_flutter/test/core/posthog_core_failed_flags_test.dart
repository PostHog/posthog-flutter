import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  test(
      'all-failed refresh announces no values and healthy recovery replaces it',
      () async {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    server.respond = (_) => PostHogResponse.json({
          'flags': {
            'flag': _flag('flag', 'placeholder', failed: true),
          },
        });
    final announced = <List<String>>[];
    client.onFeatureFlags(() => announced.add(client
        .getAllFeatureFlagResults()!
        .map((result) => result.key)
        .toList()));

    await client.reloadFeatureFlagsAsync();
    expect(client.getAllFeatureFlagResults(), isEmpty);
    expect(client.getFeatureFlag('flag'), isNull);
    expect(announced, [isEmpty]);
    expect(
        queuedProps(storage, 0)[r'$feature_flag_error'], 'evaluation_failed');
    expect(queuedProps(storage, 0).containsKey(r'$feature/flag'), isFalse);
    expect(
        queuedProps(storage, 0).containsKey(r'$active_feature_flags'), isFalse);

    server.respond = (_) => PostHogResponse.json({
          'flags': {'flag': _flag('flag', false, failed: false)},
          'errorsWhileComputingFlags': true,
        });
    await client.reloadFeatureFlagsAsync();
    expect(client.getFeatureFlag('flag'), isFalse);
    expect(announced, [
      isEmpty,
      ['flag']
    ]);
    expect(queuedProps(storage, 1)[r'$feature_flag_response'], isFalse);
    expect(queuedProps(storage, 1)[r'$feature_flag_error'],
        'errors_while_computing_flags');
  });

  for (final globalError in [null, false, true]) {
    test('failed details are not values with global error $globalError',
        () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (request) => !request.isFlags
          ? const PostHogResponse(HttpStatus.ok)
          : PostHogResponse.json({
              'flags': {
                'failed-false': _flag('failed-false', false, failed: true),
                'failed-variant':
                    _flag('failed-variant', 'placeholder', failed: true),
                'healthy-false': _flag('healthy-false', false, failed: false),
                'healthy-variant': _flag('healthy-variant', 'blue'),
              },
              // Flat mirrors must not reintroduce failed values or payloads.
              'featureFlags': {
                'failed-false': true,
                'failed-variant': 'mirror'
              },
              'featureFlagPayloads': {'failed-variant': '"mirror"'},
              if (globalError != null) 'errorsWhileComputingFlags': globalError,
              'requestId': 'request',
              'evaluatedAt': 123,
            });

      await client.reloadFeatureFlagsAsync();

      for (final key in ['failed-false', 'failed-variant']) {
        expect(client.getFeatureFlagResult(key, sendEvent: false), isNull);
        expect(client.isFeatureEnabled(key, sendEvent: false), isNull);
        expect(client.getFeatureFlag(key, sendEvent: false), isNull);
      }
      expect(getQueue(storage), isEmpty,
          reason: 'suppressed reads stay silent');
      expect(client.getFeatureFlag('healthy-false'), isFalse);
      expect(client.getFeatureFlag('healthy-variant'), 'blue');
      expect(client.getAllFeatureFlagResults()!.map((result) => result.key),
          ['healthy-false', 'healthy-variant']);
      expect(
          client
              .getFeatureFlagResult('healthy-variant', sendEvent: false)
              ?.payload,
          {'copy': 'healthy-variant'});

      for (final key in ['failed-false', 'failed-variant']) {
        expect(client.getFeatureFlagResult(key, sendEvent: true), isNull);
        expect(client.getFeatureFlag(key), isNull, reason: 'deduped null read');
      }
      client.capture('checkout');
      await client.flush();

      final delivered = server.events;
      final called = delivered
          .where((event) => event['event'] == r'$feature_flag_called')
          .toList();
      expect(called, hasLength(4));
      for (final event in called) {
        final props = event['properties']! as Map;
        final key = props[r'$feature_flag']! as String;
        expect(props.containsKey(r'$feature/failed-false'), isFalse);
        expect(props.containsKey(r'$feature/failed-variant'), isFalse);
        expect(props[r'$active_feature_flags'], ['healthy-variant']);
        if (key.startsWith('failed-')) {
          expect(props.containsKey(r'$feature_flag_response'), isTrue);
          expect(props[r'$feature_flag_response'], isNull);
          expect(
              props[r'$feature_flag_error'],
              globalError == true
                  ? 'errors_while_computing_flags,evaluation_failed'
                  : 'evaluation_failed');
          expect(props[r'$feature_flag_id'], 42);
          expect(props[r'$feature_flag_version'], 7);
          expect(props[r'$feature_flag_reason'], 'evaluation failed');
          expect(props[r'$feature_flag_request_id'], 'request');
          expect(props[r'$feature_flag_evaluated_at'], 123);
        } else {
          expect(props[r'$feature_flag_error'],
              globalError == true ? 'errors_while_computing_flags' : isNull);
        }
      }
      final capture = delivered.last['properties']! as Map;
      expect(capture.containsKey(r'$feature/failed-false'), isFalse);
      expect(capture.containsKey(r'$feature/failed-variant'), isFalse);
    });

    test('refresh with global error $globalError respects cache boundaries',
        () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (_) => PostHogResponse.json({
            'flags': {
              'on': _flag('on', true),
              'off': _flag('off', false),
              'variant': _flag('variant', 'blue'),
              'updated': _flag('updated', true),
            },
          });
      await client.reloadFeatureFlagsAsync();
      server.respond = (_) => PostHogResponse.json({
            'flags': {
              for (final key in ['on', 'off', 'variant', 'fresh-failure'])
                key: _flag(key, 'placeholder', failed: true),
              'updated': _flag('updated', false),
            },
            if (globalError != null) 'errorsWhileComputingFlags': globalError,
          });
      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('on'), globalError == true ? true : isNull);
      expect(
          client.getFeatureFlag('off'), globalError == true ? false : isNull);
      expect(client.getFeatureFlag('variant'),
          globalError == true ? 'blue' : isNull);
      expect(client.getFeatureFlagResult('variant', sendEvent: false)?.payload,
          globalError == true ? {'copy': 'variant'} : isNull);
      expect(client.getFeatureFlag('updated'), isFalse);
      expect(client.getFeatureFlag('fresh-failure'), isNull);
      expect(
          client.getAllFeatureFlagResults()!.map((result) => result.key),
          globalError == true
              ? ['on', 'off', 'variant', 'updated']
              : ['updated']);
      expect(
          queuedProps(storage, 0)[r'$feature_flag_error'],
          globalError == true
              ? 'errors_while_computing_flags'
              : 'evaluation_failed');

      // Persistence must not turn diagnostic-only details back into values.
      final reloaded = testClient(server, storage: storage);
      expect(reloaded.getFeatureFlag('fresh-failure'), isNull);
      expect(reloaded.getFeatureFlag('variant'),
          globalError == true ? 'blue' : isNull);
    });
  }
}

Map<String, Object?> _flag(String key, Object value, {bool? failed}) => {
      'key': key,
      'enabled': value is String || value == true,
      if (value is String) 'variant': value,
      if (failed != null) 'failed': failed,
      'metadata': {
        'id': 42,
        'version': 7,
        'payload': '{"copy":"$key"}',
      },
      'reason': {
        'description': failed == true ? 'evaluation failed' : 'matched'
      },
    };
