import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/persistence.dart';
import 'package:posthog_flutter/src/feature_flag_result.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  group('PostHogCore.reloadFeatureFlagsAsync', () {
    test('sends non-string person properties to /flags/', () async {
      final client = testClient(server);

      client.setPersonProperties(
        userPropertiesToSet: {'age': 30, 'beta': true, 'plan': 'pro'},
      );
      await client.reloadFeatureFlagsAsync();

      expect(_flagsRequestBody(server)['person_properties'],
          {..._sdkProperties, 'age': 30, 'beta': true, 'plan': 'pro'});
    });

    test('group properties keep their JSON types in the /flags request',
        () async {
      final client = testClient(server);

      client.setGroupPropertiesForFlags({
        'company': {'beta': true, 'seats': 50, 'tier': 'scale'},
      });
      await client.reloadFeatureFlagsAsync();

      expect(_flagsRequestBody(server)['group_properties'], {
        'company': {'beta': true, 'seats': 50, 'tier': 'scale'},
      });
    });

    test('an empty response clears stale flags and the recorded error',
        () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);

      server.respond =
          (_) => _flagsResponse({'stale-flag': _flag('stale-flag')});
      await client.reloadFeatureFlagsAsync();
      expect(client.getFeatureFlag('stale-flag'), isTrue);

      server.respond =
          (_) => const PostHogResponse(HttpStatus.internalServerError);
      await client.reloadFeatureFlagsAsync();
      expect(client.getFeatureFlag('stale-flag'), isTrue,
          reason: 'a failed refresh keeps serving the cached flags');
      expect(_storedFlagDetails(storage)['requestError'], isNotNull);

      server.respond = (_) => _flagsResponse({});
      var notified = 0;
      client.onFeatureFlags(() => notified++);
      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('stale-flag'), isNull,
          reason: 'an empty success is an answer, not a failure: '
              'stale flags must not survive it');
      expect(notified, 1);
      expect(_storedFlagDetails(storage).containsKey('requestError'), isFalse);
    });

    test('a malformed flag in the response is skipped, its neighbours stay',
        () async {
      final client = testClient(server);
      server.respond = (_) => _flagsResponse({
            'good-flag': _flag('good-flag'),
            'bad-flag': {'enabled': 'yes'},
          });

      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('good-flag'), isTrue);
      expect(client.getFeatureFlag('bad-flag'), isNull);
    });

    test('reloads queued behind one in flight get the next response', () async {
      final client = testClient(server);
      final release = Completer<void>();
      server.respond = (request) async {
        final personProperties = request.body['person_properties']! as Map;
        if (!personProperties.containsKey('plan')) await release.future;
        return _flagsResponse({
          if (personProperties['plan'] == 'pro') 'pro-flag': _flag('pro-flag'),
        });
      };

      final inFlight = client.reloadFeatureFlagsAsync();
      client.setPersonPropertiesForFlags({'plan': 'pro'});
      var displacedDone = false;
      final displaced =
          client.reloadFeatureFlagsAsync().then((_) => displacedDone = true);
      client.setPersonPropertiesForFlags({'seats': 5});
      final latest = client.reloadFeatureFlagsAsync();
      release.complete();

      await inFlight;
      expect(displacedDone, isFalse,
          reason: 'the displaced reload is answered by the request that runs '
              'next, not by the one that was already in flight');
      await displaced;
      await latest;
      expect(client.getFeatureFlag('pro-flag'), isTrue);
      expect(server.flagsRequests, hasLength(2));
    });

    test('a throwing onFeatureFlags callback does not stop the flags',
        () async {
      final client = testClient(server);
      server.respond = (_) => _flagsResponse({'beta-ui': _flag('beta-ui')});
      client.onFeatureFlags(() => throw StateError('callback failure'));

      await expectLater(client.reloadFeatureFlagsAsync(), completes);

      expect(client.getFeatureFlag('beta-ui'), isTrue);
    });
  });

  group('Feature flag reads', () {
    test('a missing key reads as null through every accessor', () async {
      final client = testClient(server);
      server.respond =
          (_) => _flagsResponse({'existing-flag': _flag('existing-flag')});
      await client.reloadFeatureFlagsAsync();

      expect(client.isFeatureEnabled('existing-flag'), isTrue);
      expect(client.getFeatureFlag('missing'), isNull);
      expect(client.getFeatureFlagResult('missing', sendEvent: false), isNull);
      expect(client.isFeatureEnabled('missing'), isNull);
    });

    test('payloads accompany only enabled flags', () async {
      final client = testClient(server);
      server.respond = (_) => _flagsResponse({
            'paid-flag': _flag('paid-flag', payload: '{"tier":"gold"}'),
            'off-flag': _flag('off-flag', enabled: false, payload: '"nope"'),
          });
      await client.reloadFeatureFlagsAsync();

      expect(
          client.getFeatureFlagResult('paid-flag', sendEvent: false)?.payload,
          {'tier': 'gold'});
      final offResult =
          client.getFeatureFlagResult('off-flag', sendEvent: false);
      expect(offResult?.enabled, isFalse);
      expect(offResult?.payload, isNull);
    });

    test('payloads decode to their JSON value, falsy ones included', () async {
      final client = testClient(server);
      const decodedBySerialized = <String, Object>{
        '"hello"': 'hello',
        '""': '',
        'false': false,
        '0': 0,
        '[1,false]': [1, false],
      };
      final serialized = decodedBySerialized.keys.toList();
      server.respond = (_) => _flagsResponse({
            for (final (i, payload) in serialized.indexed)
              'flag-$i': _flag('flag-$i', payload: payload),
          });
      await client.reloadFeatureFlagsAsync();

      for (final (i, payload) in serialized.indexed) {
        expect(
            client.getFeatureFlagResult('flag-$i', sendEvent: false)?.payload,
            decodedBySerialized[payload],
            reason: payload);
      }
    });

    for (final payload in ['{broken', '']) {
      test('a payload of "$payload", not valid JSON, reads as no payload',
          () async {
        final client = testClient(server, config: testConfig(debug: true));
        server.respond = (_) =>
            _flagsResponse({'beta-ui': _flag('beta-ui', payload: payload)});
        await client.reloadFeatureFlagsAsync();

        late final PostHogFeatureFlagResult? result;
        final lines = printedLines(() =>
            result = client.getFeatureFlagResult('beta-ui', sendEvent: false));

        expect(result?.enabled, isTrue);
        expect(result?.payload, isNull,
            reason: 'the raw string is not a payload');
        expect(lines, contains(contains('not valid JSON')));
      });
    }

    test('malformed persisted flag details are discarded, not thrown', () {
      final dir = tempDirectory();
      // Valid JSON, unexpected shape - e.g. written by another SDK version
      // sharing the same store.
      FileStorage(dir.path)
        ..setProperty(PostHogPersistedProperty.featureFlagDetails,
            <String, Object?>{'flags': 'garbage'})
        ..close();
      final storage = FileStorage(dir.path);

      final client = testClient(server, storage: storage);

      expect(() => client.capture('evt'), returnsNormally);
      expect(getQueue(storage), hasLength(1));
      expect(client.getFeatureFlag('missing'), isNull);
      expect(
          storage.getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.featureFlagDetails),
          isNull);
    });
  });

  group('Quota limiting', () {
    test('keeps serving cached flags through every channel', () async {
      final client = testClient(server);
      server.respond =
          (_) => _flagsResponse({'cached-flag': _flag('cached-flag')});
      await client.reloadFeatureFlagsAsync();

      server.respond =
          (_) => _flagsResponse({}, quotaLimited: ['feature_flags']);
      final notified = <Object?>[];
      client.onFeatureFlags(
          () => notified.add(client.getFeatureFlag('cached-flag')));
      await client.reloadFeatureFlagsAsync();

      expect(client.getFeatureFlag('cached-flag'), isTrue,
          reason: 'cached flags keep serving under quota, so every channel '
              'must report the cached state');
      expect(notified, [isTrue]);
    });
  });

  group('Person properties for flags', () {
    const context = <String, Object?>{
      r'$app_version': '9.9.9',
      r'$os_name': 'TestOS',
    };

    test('default person properties are sent with the /flags/ request',
        () async {
      final client = testClient(server, context: context);

      await client.reloadFeatureFlagsAsync();

      expect(_flagsRequestBody(server)['person_properties'],
          {...context, ..._sdkProperties});
    });

    test('explicitly set person properties override the defaults', () async {
      final client = testClient(server, context: context);

      client.setPersonPropertiesForFlags({r'$os_name': 'ManualOS'});
      await client.reloadFeatureFlagsAsync();

      expect(_flagsRequestBody(server)['person_properties'],
          {...context, ..._sdkProperties, r'$os_name': 'ManualOS'});
    });

    test('person properties with a DateTime reach /flags/ as a string',
        () async {
      final client = testClient(server);

      client.setPersonPropertiesForFlags({'signed_up': DateTime.utc(2024)});
      client.setGroupPropertiesForFlags({
        'company': {'founded': DateTime.utc(2020)},
      });
      await client.reloadFeatureFlagsAsync();

      final body = _flagsRequestBody(server);
      expect(body['person_properties'],
          {..._sdkProperties, 'signed_up': '2024-01-01T00:00:00.000Z'});
      expect(body['group_properties'], {
        'company': {'founded': '2020-01-01T00:00:00.000Z'},
      });
    });

    test('identify user properties feed the next /flags/ request', () async {
      final client = testClient(server);

      client.identify(
        'user-1',
        userProperties: {'plan': 'pro'},
        userPropertiesSetOnce: {'plan': 'trial', 'signup_source': 'ads'},
      );

      final body = await server.waitForFlagsRequest(0);
      expect(body['person_properties'],
          {..._sdkProperties, 'plan': 'pro', 'signup_source': 'ads'},
          reason: r'$set wins over $set_once for the same key');
    });
  });

  group('Feature flag request body', () {
    test('carries the device id through identify and reset', () async {
      final dir = tempDirectory();
      final client = testClient(server, storage: FileStorage(dir.path));
      final deviceId = client.getDistinctId();

      await client.reloadFeatureFlagsAsync();
      expect(_flagsRequestBody(server)[r'$device_id'], deviceId);

      client.identify('user-123');
      client.reset();
      await client.reloadFeatureFlagsAsync();

      final body = _flagsRequestBody(server);
      expect(body['distinct_id'], isNot(anyOf('user-123', deviceId)));
      expect(body[r'$device_id'], deviceId,
          reason: 'device-level bucketing must not change with the user');

      client.close();
      final restarted = testClient(server, storage: FileStorage(dir.path));
      await restarted.reloadFeatureFlagsAsync();
      expect(_flagsRequestBody(server)[r'$device_id'], deviceId);
    });

    test('carries the time zone a platform provides', () async {
      final client = testClient(server, timezone: 'Europe/Berlin');

      await client.reloadFeatureFlagsAsync();

      expect(_flagsRequestBody(server)['timezone'], 'Europe/Berlin');
    });

    test('has no time zone by default', () async {
      final client = testClient(server);

      await client.reloadFeatureFlagsAsync();

      expect(_flagsRequestBody(server).containsKey('timezone'), isFalse);
    });
  });

  group('Feature flag requests', () {
    for (final status in [502, 504]) {
      test('retry once after HTTP $status', () async {
        final client = testClient(server);
        var attempts = 0;
        server.respond = (_) => ++attempts == 1
            ? PostHogResponse(status)
            : _flagsResponse({'beta-ui': _flag('beta-ui')});

        await client.reloadFeatureFlagsAsync();
        expect(client.getFeatureFlag('beta-ui'), isTrue);
        expect(server.flagsRequests, hasLength(2));
      });
    }

    test('retry once after a network error', () async {
      final client = testClient(server);
      var attempts = 0;
      server.respond = (_) => ++attempts == 1
          ? const PostHogResponse.dropped()
          : _flagsResponse({'beta-ui': _flag('beta-ui')});

      await client.reloadFeatureFlagsAsync();
      expect(client.getFeatureFlag('beta-ui'), isTrue);
      expect(server.flagsRequests, hasLength(2));
    });

    test('stop after one retry', () async {
      final client = testClient(server);
      server.respond = (_) => const PostHogResponse(HttpStatus.badGateway);

      await client.reloadFeatureFlagsAsync();
      expect(client.getFeatureFlag('beta-ui'), isNull);
      expect(server.flagsRequests, hasLength(2));
    });

    test('time out after ten seconds, and once more after the retry', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => Completer<PostHogResponse>().future;
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api, storage: storage);

        client.reloadFeatureFlagsAsync();
        async.elapse(const Duration(seconds: 10));
        expect(api.flagsRequests, hasLength(1));
        async.elapse(const Duration(milliseconds: 300));
        expect(api.flagsRequests, hasLength(2));
        expect(_storedFlagDetails(storage), isEmpty);
        async.elapse(const Duration(seconds: 10));

        expect(
            _storedFlagDetails(storage)['requestError'], {'type': 'timeout'});
      });
    });

    for (final status in [408, 429, 500, 503]) {
      test('are not retried for HTTP $status', () async {
        final client = testClient(server);
        server.respond = (_) => PostHogResponse(status);

        await client.reloadFeatureFlagsAsync();
        expect(client.getFeatureFlag('beta-ui'), isNull);
        expect(server.flagsRequests, hasLength(1));
      });
    }
  });

  group(r'$active_feature_flags', () {
    test('lists only enabled flags', () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (_) => _flagsResponse({
            'on-flag': _flag('on-flag'),
            'variant-flag': _flag('variant-flag', variant: 'test'),
            'off-flag': _flag('off-flag', enabled: false),
          });
      await client.reloadFeatureFlagsAsync();

      client.capture('evt');

      final props = queuedProps(storage, 0);
      expect(props[r'$active_feature_flags'], ['on-flag', 'variant-flag']);
      expect(props[r'$feature/off-flag'], isFalse);
    });

    test('is left out when no flag is enabled', () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (_) =>
          _flagsResponse({'off-flag': _flag('off-flag', enabled: false)});
      await client.reloadFeatureFlagsAsync();

      client.capture('evt');

      expect(queuedProps(storage, 0).containsKey(r'$active_feature_flags'),
          isFalse);
    });
  });

  group(r'$feature_flag_called tracking', () {
    late FileStorage storage;
    late DesktopPostHog client;
    late Map<String, Object?> flags;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage);
      flags = {'beta-ui': _flag('beta-ui')};
      server.respond = (_) => _flagsResponse(flags);
    });

    test('reports a flag value once, even across reloads', () async {
      await client.reloadFeatureFlagsAsync();

      client.getFeatureFlag('beta-ui');
      client.isFeatureEnabled('beta-ui');
      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      expect(_flagCalledCount(storage), 1);
    });

    test('reports a flag again when its value changes', () async {
      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      flags = {'beta-ui': _flag('beta-ui', variant: 'test')};
      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      expect(_flagCalledCount(storage), 2);
    });

    test('reports a flag again after reset', () async {
      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      client.reset();
      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      expect(_flagCalledCount(storage), 2);
    });

    test('carries whether the flag is linked to an experiment', () async {
      flags = {'beta-ui': _flag('beta-ui', hasExperiment: true)};
      await client.reloadFeatureFlagsAsync();

      client.getFeatureFlag('beta-ui');

      expect(
          _flagCalledProps(storage)[r'$feature_flag_has_experiment'], isTrue);
    });
  });

  group(r'Minimal $feature_flag_called events', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage, context: {
        r'$os_name': 'TestOS',
        r'$app_version': '1.0.0',
        r'$device_type': 'Desktop',
      });
      client.register({
        'team': 'growth',
        'utm_source': 'newsletter',
        r'$referring_domain': 'example.com',
        r'$referrer': 'https://example.com/private?token=1',
      });
    });

    Future<void> loadFlag({bool? minimal, bool? hasExperiment}) async {
      server.respond = (_) => _flagsResponse(
            {'beta-ui': _flag('beta-ui', hasExperiment: hasExperiment)},
            minimalFlagCalledEvents: minimal,
          );
      await client.reloadFeatureFlagsAsync();
    }

    test('keep only the allowlisted properties for a flag without experiment',
        () async {
      await loadFlag(minimal: true, hasExperiment: false);

      client.getFeatureFlag('beta-ui');

      expect(_flagCalledProps(storage).keys.toSet(), {
        r'$feature_flag',
        r'$feature_flag_response',
        r'$feature_flag_has_experiment',
        r'$process_person_profile',
        r'$session_id',
        r'$lib',
        r'$lib_version',
        r'$os_name',
        r'$app_version',
        r'$referring_domain',
        'utm_source',
      });
    });

    // (description, server gate, flag has_experiment)
    const fullEventCases = <(String, bool?, bool?)>[
      ('the server does not ask for them', null, false),
      ('the flag is linked to an experiment', true, true),
      ('the experiment link is unknown', true, null),
    ];

    for (final (description, minimal, hasExperiment) in fullEventCases) {
      test('are not sent when $description', () async {
        await loadFlag(minimal: minimal, hasExperiment: hasExperiment);

        client.getFeatureFlag('beta-ui');

        final props = _flagCalledProps(storage);
        expect(props['team'], 'growth');
        expect(props[r'$feature/beta-ui'], isTrue);
      });
    }

    test('stay on through a failed flags reload', () async {
      await loadFlag(minimal: true, hasExperiment: false);
      server.respond = (_) => const PostHogResponse(HttpStatus.badRequest);
      await client.reloadFeatureFlagsAsync();

      client.getFeatureFlag('beta-ui');

      expect(_flagCalledProps(storage).containsKey('team'), isFalse);
    });
  });

  group('Feature flag preloading', () {
    test('a new client requests /flags/ once when preloading is on', () async {
      final client =
          testClient(server, config: testConfig(preloadFeatureFlags: true));
      final loaded = Completer<void>();
      client.onFeatureFlags(loaded.complete);

      await loaded.future;

      expect(server.flagsRequests, hasLength(1));
    });

    test('no /flags/ request is made when preloading is off', () async {
      final client = testClient(server);

      await client.reloadFeatureFlagsAsync();

      expect(server.flagsRequests, hasLength(1),
          reason: 'a preload would still be in flight, so the reload above '
              'would make a second request');
    });
  });

  group('Flags cached by an earlier launch', () {
    /// Runs a launch that caches in [dir] the flags [api] answers.
    void launchEarlier(FakeAsync async, PostHogApiFake api, Directory dir) {
      final client = testClient(api, storage: FileStorage(dir.path));
      client.reloadFeatureFlagsAsync();
      async.flushMicrotasks();
      client.close();
    }

    test('are announced before the preload response, which follows', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => _flagsResponse({'beta-ui': _flag('beta-ui')});
      final dir = tempDirectory();
      fakeAsync((async) {
        launchEarlier(async, api, dir);
        final response = Completer<PostHogResponse>();
        api.respond = (_) => response.future;
        final client = testClient(api,
            config: testConfig(preloadFeatureFlags: true),
            storage: FileStorage(dir.path));
        final announced = <Object?>[];
        client.onFeatureFlags(
            () => announced.add(client.getFeatureFlag('beta-ui')));

        async.elapse(Duration.zero);
        expect(announced, [isTrue]);

        response.complete(
            _flagsResponse({'beta-ui': _flag('beta-ui', enabled: false)}));
        async.flushMicrotasks();
        expect(announced, [isTrue, isFalse]);
      });
    });

    test('are not announced after a preload response that came first', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => _flagsResponse({'beta-ui': _flag('beta-ui')});
      final dir = tempDirectory();
      fakeAsync((async) {
        launchEarlier(async, api, dir);
        api.respond = (_) =>
            _flagsResponse({'beta-ui': _flag('beta-ui', enabled: false)});
        final client = testClient(api,
            config: testConfig(preloadFeatureFlags: true),
            storage: FileStorage(dir.path));
        final announced = <Object?>[];
        client.onFeatureFlags(
            () => announced.add(client.getFeatureFlag('beta-ui')));

        async.flushMicrotasks();
        async.elapse(Duration.zero);

        expect(announced, [isFalse],
            reason: 'the cached flags are stale once the response is in');
      });
    });
  });
}

/// The person properties every `/flags/` request of the desktop client
/// carries.
const _sdkProperties = <String, Object?>{
  r'$lib': postHogFlutterSdkName,
  r'$lib_version': postHogFlutterVersion,
};

Map<String, Object?> _flag(
  String key, {
  bool enabled = true,
  String? variant,
  String? payload,
  bool? hasExperiment,
}) =>
    {
      'key': key,
      'enabled': enabled,
      if (variant != null) 'variant': variant,
      if (payload != null || hasExperiment != null)
        'metadata': {
          if (payload != null) 'payload': payload,
          if (hasExperiment != null) 'has_experiment': hasExperiment,
        },
    };

PostHogResponse _flagsResponse(
  Map<String, Object?> flags, {
  List<String>? quotaLimited,
  bool? minimalFlagCalledEvents,
}) =>
    PostHogResponse.json({
      'flags': flags,
      if (quotaLimited != null) 'quotaLimited': quotaLimited,
      if (minimalFlagCalledEvents != null)
        'minimalFlagCalledEvents': minimalFlagCalledEvents,
    });

Map<String, Object?> _flagCalledProps(FileStorage storage) =>
    queuedPropsOf(storage, r'$feature_flag_called');

int _flagCalledCount(FileStorage storage) => queuedEvents(storage)
    .where((event) => event == r'$feature_flag_called')
    .length;

Map<String, Object?> _flagsRequestBody(PostHogApiFake api) =>
    api.flagsRequests.last.body;

Map<String, Object?> _storedFlagDetails(FileStorage storage) =>
    storage.getProperty<Map<String, Object?>>(
        PostHogPersistedProperty.featureFlagDetails) ??
    {};
