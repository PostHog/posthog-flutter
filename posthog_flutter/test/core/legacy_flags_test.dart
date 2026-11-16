import 'package:flutter_test/flutter_test.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  test(
      'legacy: bool, variant, and JSON payload are available through the client',
      () async {
    final client = testClient(server);
    server.respond = (_) => PostHogResponse.json({
          'featureFlags': {'on': true, 'off': false, 'variant': 'blue'},
          'featureFlagPayloads': {
            'on': '{"color":"green"}',
            'off': '{"hidden":true}',
            'variant': '"hello"',
          },
        });

    await client.reloadFeatureFlagsAsync();

    expect(client.getFeatureFlag('on'), isTrue);
    expect(client.getFeatureFlag('off'), isFalse);
    expect(client.getFeatureFlag('variant'), 'blue');
    expect(client.getFeatureFlagResult('on', sendEvent: false)?.payload,
        {'color': 'green'});
    expect(
        client.getFeatureFlagResult('off', sendEvent: false)?.payload, isNull);
    final result = client.getFeatureFlagResult('variant', sendEvent: false)!;
    expect(result.enabled, isTrue);
    expect(result.variant, 'blue');
    expect(result.payload, 'hello');
    expect(server.flagsRequests, hasLength(1));
  });

  for (final rich in <Map<String, Object?>>[
    {},
    {
      'flag': {'key': 'flag', 'enabled': false}
    },
  ]) {
    test('rich flags $rich take precedence over legacy flags', () async {
      final client = testClient(server);
      server.respond = (_) => PostHogResponse.json({
            'featureFlags': {'flag': true},
          });
      await client.reloadFeatureFlagsAsync();
      expect(client.getFeatureFlag('flag'), isTrue);

      server.respond = (_) => PostHogResponse.json({
            'flags': rich,
            'featureFlags': {'flag': true, 'legacy-only': true},
            'featureFlagPayloads': {'flag': '"legacy"'},
          });
      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('flag'), rich.isEmpty ? isNull : isFalse);
      expect(client.getFeatureFlag('legacy-only'), isNull);
      expect(client.getFeatureFlagResult('flag', sendEvent: false)?.payload,
          isNull);
    });
  }

  test('legacy: malformed flags and payloads do not affect other flags',
      () async {
    final client = testClient(server);
    server.respond = (_) => PostHogResponse.json({
          'featureFlags': {
            'good': true,
            'bad-value': 1,
            'null-value': null,
            'bad-payload': 'blue',
            'bad-json': true,
          },
          'featureFlagPayloads': {
            'good': '[1,true]',
            'bad-payload': {'decoded': true},
            'bad-json': '{broken',
          },
        });

    await client.reloadFeatureFlagsAsync();

    expect(client.getFeatureFlag('good'), isTrue);
    expect(client.getFeatureFlagResult('good', sendEvent: false)?.payload,
        [1, true]);
    expect(client.getFeatureFlag('bad-value'), isNull);
    expect(client.getFeatureFlag('null-value'), isNull);
    expect(client.getFeatureFlag('bad-payload'), 'blue');
    expect(
        client.getFeatureFlagResult('bad-payload', sendEvent: false)?.payload,
        isNull);
    expect(client.getFeatureFlag('bad-json'), isTrue);
    expect(client.getFeatureFlagResult('bad-json', sendEvent: false)?.payload,
        isNull);
  });

  test(
      'legacy: a partial response merges and a full response replaces the cache',
      () async {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    server.respond = (_) => PostHogResponse.json({
          'featureFlags': {'retained': true, 'updated': true},
          'featureFlagPayloads': {'retained': '"cached"'},
        });
    await client.reloadFeatureFlagsAsync();

    server.respond = (_) => PostHogResponse.json({
          'featureFlags': {'updated': false, 'new': 'blue', 'bad': []},
          'errorsWhileComputingFlags': true,
        });
    await client.reloadFeatureFlagsAsync();

    expect(client.getFeatureFlag('retained'), isTrue);
    expect(client.getFeatureFlagResult('retained', sendEvent: false)?.payload,
        'cached');
    expect(client.getFeatureFlag('updated'), isFalse);
    expect(client.getFeatureFlag('new'), 'blue');
    expect(queuedProps(storage, 0)[r'$feature_flag_error'],
        'errors_while_computing_flags');

    server.respond = (_) => PostHogResponse.json({'featureFlags': {}});
    await client.reloadFeatureFlagsAsync();
    expect(client.getFeatureFlag('retained'), isNull);
    expect(client.getFeatureFlag('updated'), isNull);
    expect(client.getFeatureFlag('new'), isNull);
  });

  test('legacy: request metadata is retained without inventing details',
      () async {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    client.register({'team': 'growth'});
    server.respond = (_) => PostHogResponse.json({
          'featureFlags': {'flag': true},
          'featureFlagPayloads': {'flag': '{"enabled":true}'},
          'requestId': 'legacy-request',
          'evaluatedAt': 123,
          'minimalFlagCalledEvents': true,
        });

    await client.reloadFeatureFlagsAsync();
    expect(client.getFeatureFlag('flag'), isTrue);

    final props = queuedProps(storage, 0);
    expect(props[r'$feature_flag_request_id'], 'legacy-request');
    expect(props[r'$feature_flag_evaluated_at'], 123);
    expect(props['team'], 'growth');
    expect(props[r'$feature/flag'], isTrue);
    for (final property in [
      r'$feature_flag_id',
      r'$feature_flag_version',
      r'$feature_flag_reason',
      r'$feature_flag_has_experiment',
    ]) {
      expect(props.containsKey(property), isFalse);
    }
  });

  test('legacy: quota retains the cache and marks a missing flag', () async {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    server.respond = (_) => PostHogResponse.json({
          'featureFlags': {'cached': true},
        });
    await client.reloadFeatureFlagsAsync();

    server.respond = (_) => PostHogResponse.json({
          'featureFlags': {'cached': false},
          'quotaLimited': ['feature_flags'],
        });
    await client.reloadFeatureFlagsAsync();

    expect(client.getFeatureFlag('cached'), isTrue);
    expect(client.getFeatureFlag('missing'), isNull);
    expect(queuedProps(storage, 1)[r'$feature_flag_error'], 'quota_limited');
  });
}
