import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/persistence.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;
  late Directory dir;

  setUp(() async {
    server = await LocalPostHogServer.start();
    dir = tempDirectory();
  });

  /// A launch of the app with [bootstrap]: its client, and the storage the
  /// client keeps its state in.
  (DesktopPostHog, FileStorage) launch([PostHogBootstrapConfig? bootstrap]) {
    final storage = FileStorage(dir.path);
    final client = testClient(server,
        config: testConfig(bootstrap: bootstrap), storage: storage);
    return (client, storage);
  }

  group('Bootstrapped identity', () {
    test('seeds the anonymous id on a fresh install', () {
      final (client, storage) =
          launch(const PostHogBootstrapConfig(distinctId: 'anon-abc'));

      expect(client.getDistinctId(), 'anon-abc');
      expect(_isIdentified(storage), isFalse);
      client.identify('user-1');
      expect(queuedPropsOf(storage, r'$identify')[r'$anon_distinct_id'],
          'anon-abc');
    });

    test('seeds an identified user, but not as the device id', () async {
      final (client, storage) = launch(const PostHogBootstrapConfig(
          distinctId: 'user-123', isIdentifiedId: true));

      await client.reloadFeatureFlagsAsync();

      expect(client.getDistinctId(), 'user-123');
      expect(_isIdentified(storage), isTrue);
      expect(server.flagsRequests.last.body[r'$device_id'], isNot('user-123'),
          reason: 'device-level bucketing must never use the person id');
      expect(getQueue(storage), isEmpty,
          reason: 'a fresh install has no anonymous history to link');
    });

    test('never replaces a stored anonymous id', () {
      final (earlier, _) = launch();
      final anonymousId = earlier.getDistinctId();
      earlier.close();

      final (client, _) =
          launch(const PostHogBootstrapConfig(distinctId: 'anon-new'));

      expect(client.getDistinctId(), anonymousId);
    });

    test('an identified bootstrap merges a stored anonymous user', () {
      final (earlier, _) = launch();
      final anonymousId = earlier.getDistinctId();
      earlier.close();

      final (client, storage) = launch(const PostHogBootstrapConfig(
          distinctId: 'user-123', isIdentifiedId: true));

      expect(client.getDistinctId(), 'user-123');
      final identify = queuedPropsOf(storage, r'$identify');
      expect(identify[r'$anon_distinct_id'], anonymousId);
    });

    test('an identified bootstrap keeps a different identified user', () {
      final (earlier, _) = launch();
      earlier
        ..identify('user-existing')
        ..close();

      final (client, storage) = launch(const PostHogBootstrapConfig(
          distinctId: 'user-123', isIdentifiedId: true));

      expect(client.getDistinctId(), 'user-existing');
      expect(queuedEvents(storage), [r'$identify']);
    });

    test('an identified bootstrap of the stored anonymous id sends nothing',
        () {
      final (earlier, _) = launch();
      final anonymousId = earlier.getDistinctId();
      earlier.close();

      final (client, storage) = launch(PostHogBootstrapConfig(
          distinctId: anonymousId, isIdentifiedId: true));

      expect(client.getDistinctId(), anonymousId);
      expect(_isIdentified(storage), isTrue);
      expect(getQueue(storage), isEmpty);
    });

    test('an identified bootstrap is reconciled while opted out, silently', () {
      final (earlier, _) = launch();
      earlier
        ..getDistinctId()
        ..optOut()
        ..close();

      final (client, storage) = launch(const PostHogBootstrapConfig(
          distinctId: 'user-123', isIdentifiedId: true));

      expect(client.getDistinctId(), 'user-123');
      expect(_isIdentified(storage), isTrue,
          reason: 'opting out stops events, not the local identity');
      expect(getQueue(storage), isEmpty);
    });
  });

  group('Bootstrapped feature flags', () {
    test('are served before the first flags response', () {
      final (client, _) = launch(const PostHogBootstrapConfig(featureFlags: {
        'beta-ui': true,
        'checkout': 'variant-a',
      }, featureFlagPayloads: {
        'checkout': {'color': 'blue'},
      }));

      expect(client.getFeatureFlag('beta-ui'), isTrue);
      expect(client.getFeatureFlag('checkout'), 'variant-a');
      expect(client.getFeatureFlagResult('checkout', sendEvent: false)?.payload,
          {'color': 'blue'});
    });

    test('are not served when disabled, nor are their payloads', () {
      final (client, _) = launch(const PostHogBootstrapConfig(
          featureFlags: {'enabled': true, 'disabled': false, 'empty': ''},
          featureFlagPayloads: {'disabled': 'hidden'}));

      expect(client.getFeatureFlag('enabled'), isTrue);
      expect(client.getFeatureFlag('disabled'), isNull);
      expect(client.getFeatureFlag('empty'), isNull);
      expect(client.getFeatureFlagResult('disabled', sendEvent: false)?.payload,
          isNull);
    });

    test('replace flags stored by an earlier session', () async {
      server.respond = (_) => _flagsResponse({
            'checkout': _flag('checkout', enabled: false),
            'other': _flag('other'),
          });
      final (earlier, _) = launch();
      await earlier.reloadFeatureFlagsAsync();
      earlier.close();

      final (client, _) = launch(
          const PostHogBootstrapConfig(featureFlags: {'checkout': true}));

      expect(client.getFeatureFlag('checkout'), isTrue);
      expect(client.getFeatureFlag('other'), isNull);
    });

    test('are replaced by a complete flags response', () async {
      final (client, _) = launch(const PostHogBootstrapConfig(featureFlags: {
        'beta-ui': 'variant-a',
        'legacy': true
      }, featureFlagPayloads: {
        'beta-ui': {'color': 'blue'},
      }));
      server.respond = (_) =>
          _flagsResponse({'beta-ui': _flag('beta-ui', variant: 'variant-b')});

      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('beta-ui'), 'variant-b');
      expect(client.getFeatureFlagResult('beta-ui', sendEvent: false)?.payload,
          isNull);
      expect(client.getFeatureFlag('legacy'), isNull);
    });

    test('keep what an errored flags response did not compute', () async {
      final (client, _) = launch(const PostHogBootstrapConfig(
          featureFlags: {'beta-ui': true, 'legacy': true}));
      server.respond = (_) => _flagsResponse(
          {'beta-ui': _flag('beta-ui', enabled: false)},
          errorsWhileComputingFlags: true);

      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('beta-ui'), isFalse);
      expect(client.getFeatureFlag('legacy'), isTrue);
    });

    test('are dropped by reset', () async {
      final (client, _) =
          launch(const PostHogBootstrapConfig(featureFlags: {'legacy': true}));
      server.respond = (_) => _flagsResponse({});

      client.reset();
      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('legacy'), isNull);
    });

    test('notify flags listeners right after setup', () async {
      final (client, _) =
          launch(const PostHogBootstrapConfig(featureFlags: {'beta-ui': true}));
      final loaded = Completer<void>();
      client.onFeatureFlags(loaded.complete);

      await loaded.future;

      expect(client.getFeatureFlag('beta-ui'), isTrue);
      await client.reloadFeatureFlagsAsync();
      expect(server.flagsRequests, hasLength(1),
          reason: 'the bootstrapped flags need no request of their own');
    });

    test(r'are reported on $feature_flag_called until flags load', () async {
      final (client, storage) =
          launch(const PostHogBootstrapConfig(featureFlags: {
        'beta-ui': 'variant-a',
      }, featureFlagPayloads: {
        'beta-ui': {'color': 'blue'},
      }));

      client.getFeatureFlag('beta-ui');
      server.respond = (_) =>
          _flagsResponse({'beta-ui': _flag('beta-ui', variant: 'variant-b')});
      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      final calls = [
        for (final message in getQueue(storage))
          if (message['event'] == r'$feature_flag_called')
            message['properties']! as Map<String, Object?>,
      ];
      expect(calls, hasLength(2));
      expect(calls[0][r'$feature_flag_response'], 'variant-a');
      expect(calls[0][r'$feature_flag_bootstrapped_response'], 'variant-a');
      expect(
          calls[0][r'$feature_flag_bootstrapped_payload'], {'color': 'blue'});
      expect(calls[0][r'$used_bootstrap_value'], isTrue);
      expect(calls[1][r'$feature_flag_response'], 'variant-b');
      expect(calls[1][r'$used_bootstrap_value'], isFalse);
    });

    test(r'are reported unused after a quota-limited flags response', () async {
      final (client, storage) =
          launch(const PostHogBootstrapConfig(featureFlags: {'beta-ui': true}));
      server.respond =
          (_) => _flagsResponse({}, quotaLimited: ['feature_flags']);
      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('beta-ui'), isTrue,
          reason: 'cached flags keep serving under the quota limit');

      final props = queuedPropsOf(storage, r'$feature_flag_called');
      expect(props[r'$feature_flag_bootstrapped_response'], isTrue);
      expect(props[r'$used_bootstrap_value'], isFalse,
          reason: 'PostHog answered the /flags request');
    });

    test(r'are not reported for flags that were not bootstrapped', () async {
      final (client, storage) =
          launch(const PostHogBootstrapConfig(featureFlags: {'beta-ui': true}));
      server.respond = (_) => _flagsResponse({'other': _flag('other')});
      await client.reloadFeatureFlagsAsync();

      client.getFeatureFlag('other');

      final props = queuedPropsOf(storage, r'$feature_flag_called');
      expect(props.containsKey(r'$used_bootstrap_value'), isFalse);
      expect(
          props.containsKey(r'$feature_flag_bootstrapped_response'), isFalse);
    });
  });
}

bool _isIdentified(FileStorage storage) =>
    storage.getProperty<String>(PostHogPersistedProperty.personMode) ==
    'identified';

Map<String, Object?> _flag(String key,
        {bool enabled = true, String? variant}) =>
    {
      'key': key,
      'enabled': enabled,
      if (variant != null) 'variant': variant,
    };

PostHogResponse _flagsResponse(
  Map<String, Object?> flags, {
  bool errorsWhileComputingFlags = false,
  List<String>? quotaLimited,
}) =>
    PostHogResponse.json({
      'flags': flags,
      'errorsWhileComputingFlags': errorsWhileComputingFlags,
      if (quotaLimited != null) 'quotaLimited': quotaLimited,
    });
