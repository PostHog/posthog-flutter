import 'dart:async';

import 'package:posthog_dart/posthog_dart.dart';
import 'package:posthog_dart/src/event_emitter.dart';
import 'package:posthog_dart/src/feature_flag_utils.dart';
import 'package:posthog_dart/src/http.dart';
import 'package:posthog_dart/src/posthog_core.dart';
import 'package:posthog_dart/src/uuid.dart';
import 'package:test/test.dart';

/// Helper to extract the queue messages from storage.
List<Map<String, Object?>> getQueue(PostHogStorage storage) {
  final raw =
      storage.getProperty<List<Object?>>(PostHogPersistedProperty.queue);
  if (raw == null) return [];
  return raw.cast<Map<String, Object?>>();
}

/// Helper to get a queued event message at [index].
Map<String, Object?> getMessage(PostHogStorage storage, int index) {
  return getQueue(storage)[index]['message'] as Map<String, Object?>;
}

/// Helper to get properties from a queued event at [index].
Map<String, Object?> getProps(PostHogStorage storage, int index) {
  return getMessage(storage, index)['properties'] as Map<String, Object?>;
}

/// Test PostHog client that captures fetch calls instead of making real HTTP requests.
class TestPostHogClient extends PostHogCore {
  final List<({String url, PostHogFetchOptions options})> fetchCalls = [];
  PostHogFetchResponse Function(String url, PostHogFetchOptions options)?
      fetchHandler;

  final PostHogStorage testStorage;

  // ignore: use_super_parameters
  TestPostHogClient(
    super.apiKey, {
    super.options,
    PostHogStorage? storage,
  })  : testStorage = storage ?? InMemoryStorage(),
        super(storage: storage);

  @override
  Future<PostHogFetchResponse> fetch(
      String url, PostHogFetchOptions options) async {
    fetchCalls.add((url: url, options: options));
    if (fetchHandler != null) {
      return fetchHandler!(url, options);
    }
    return const PostHogFetchResponse(status: 200, body: '{"status": "ok"}');
  }

  @override
  String getLibraryId() => 'posthog-dart-test';

  @override
  String getLibraryVersion() => '0.0.1';

  @override
  String? getCustomUserAgent() => 'posthog-dart-test/0.0.1';
}

void main() {
  group('PostHogCore', () {
    late TestPostHogClient posthog;
    late InMemoryStorage storage;

    setUp(() {
      storage = InMemoryStorage();
      posthog = TestPostHogClient(
        'test-api-key',
        options: const PostHogCoreOptions(
          host: 'https://us.i.posthog.com',
          flushAt: 100, // High so we don't auto-flush
          preloadFeatureFlags: false,
        ),
        storage: storage,
      );
    });

    test('should initialize with default values', () {
      expect(posthog.apiKey, 'test-api-key');
      expect(posthog.host, 'https://us.i.posthog.com');
      expect(posthog.isDisabled, false);
      expect(posthog.optedOut, false);
    });

    test('should throw on empty api key', () {
      expect(
        () => TestPostHogClient('', storage: InMemoryStorage()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should generate anonymous ID', () {
      final anonId = posthog.getAnonymousId();
      expect(anonId, isNotEmpty);
      // Should return same ID on subsequent calls
      expect(posthog.getAnonymousId(), anonId);
    });

    test('should return anonymous ID as distinct ID when not identified', () {
      final anonId = posthog.getAnonymousId();
      expect(posthog.getDistinctId(), anonId);
    });

    test('should capture events', () {
      posthog.capture('test_event', properties: {'key': 'value'});

      final queue = getQueue(storage);
      expect(queue.length, 1);

      final message = getMessage(storage, 0);
      final props = getProps(storage, 0);
      expect(message['event'], 'test_event');
      expect(props['key'], 'value');
      expect(props[r'$lib'], 'posthog-dart-test');
    });

    test('should identify user', () {
      posthog.identify('user-123');

      expect(posthog.getDistinctId(), 'user-123');
      expect(
        storage.getProperty<String>(PostHogPersistedProperty.personMode),
        'identified',
      );
    });

    test('should not capture when opted out', () {
      posthog.optOut();
      posthog.capture('test_event');

      expect(getQueue(storage), isEmpty);
    });

    test('should opt in and capture', () {
      posthog.optOut();
      posthog.optIn();
      posthog.capture('test_event');

      expect(getQueue(storage).length, 1);
    });

    test('should reset state', () {
      posthog.identify('user-123');
      posthog.capture('test_event');

      posthog.reset();

      expect(posthog.getDistinctId(), isNot('user-123'));
      expect(
        storage.getProperty<String>(PostHogPersistedProperty.personMode),
        isNull,
      );
      // Queue should be preserved
      expect(getQueue(storage), isNotEmpty);
    });

    test('should manage session ID', () {
      final sessionId = posthog.getSessionId();
      expect(sessionId, isNotEmpty);
      // Same session within expiration
      expect(posthog.getSessionId(), sessionId);
    });

    test('should reset session ID', () {
      final sessionId = posthog.getSessionId();
      posthog.resetSessionId();
      final newSessionId = posthog.getSessionId();
      expect(newSessionId, isNot(sessionId));
    });

    test('should register super properties', () {
      posthog.register({'app_version': '1.0.0'});
      posthog.capture('test_event');

      expect(getProps(storage, 0)['app_version'], '1.0.0');
    });

    test('should unregister super properties', () {
      posthog.register({'app_version': '1.0.0', 'platform': 'web'});
      posthog.unregister('app_version');
      posthog.capture('test_event');

      final props = getProps(storage, 0);
      expect(props['app_version'], isNull);
      expect(props['platform'], 'web');
    });

    test('should register session properties', () {
      posthog.registerForSession({'screen': 'home'});
      posthog.capture('test_event');

      expect(getProps(storage, 0)['screen'], 'home');
    });

    test('should set person properties for flags', () {
      posthog
          .setPersonPropertiesForFlags({'role': 'admin'}, reloadFlags: false);

      final stored = storage.getProperty<Map<String, Object?>>(
          PostHogPersistedProperty.personProperties);
      expect(stored?['role'], 'admin');
    });

    test('should create alias', () {
      posthog.alias('new-alias');

      final message = getMessage(storage, 0);
      final props = getProps(storage, 0);
      expect(message['event'], r'$create_alias');
      expect(props['alias'], 'new-alias');
    });

    test('should handle group identification', () {
      posthog
          .group('company', 'company-123', groupProperties: {'name': 'Acme'});

      final queue = getQueue(storage);
      expect(queue, isNotEmpty);
      final hasGroupIdentify = queue.any((item) {
        final msg = item['message'] as Map<String, Object?>;
        return msg['event'] == r'$groupidentify';
      });
      expect(hasGroupIdentify, true);
    });

    test('should not process person calls when personProfiles is never', () {
      final client = TestPostHogClient(
        'test-key',
        options: const PostHogCoreOptions(
          personProfiles: PersonProfiles.never,
          preloadFeatureFlags: false,
        ),
        storage: InMemoryStorage(),
      );

      client.identify('user-123');

      // Should not have changed the distinct ID
      expect(client.getDistinctId(), isNot('user-123'));
    });

    test('should handle disabled state', () {
      final client = TestPostHogClient(
        'test-key',
        options: const PostHogCoreOptions(
          disabled: true,
          preloadFeatureFlags: false,
        ),
        storage: InMemoryStorage(),
      );

      client.capture('test_event');
      expect(getQueue(client.testStorage), isEmpty);
    });

    test('should flush events', () async {
      posthog.capture('event1');
      posthog.capture('event2');

      await posthog.flush();

      // Queue should be empty after flush
      expect(getQueue(storage), isEmpty);

      // Should have made a fetch call
      expect(posthog.fetchCalls.length, 1);
      expect(posthog.fetchCalls[0].url, 'https://us.i.posthog.com/batch/');
    });

    test('should respect before_send hook', () {
      final clientStorage = InMemoryStorage();
      final client = TestPostHogClient(
        'test-key',
        options: PostHogCoreOptions(
          preloadFeatureFlags: false,
          beforeSend: [
            (event) {
              if (event.event == 'drop_me') return null;
              return event;
            },
          ],
        ),
        storage: clientStorage,
      );

      client.capture('keep_me');
      client.capture('drop_me');
      client.capture('keep_me_too');

      final queue = getQueue(clientStorage);
      expect(queue.length, 2);
      expect(getMessage(clientStorage, 0)['event'], 'keep_me');
      expect(getMessage(clientStorage, 1)['event'], 'keep_me_too');
    });
  });

  group('UUIDv7', () {
    test('should generate valid UUID format', () {
      final uuid = generateUuidV7();
      expect(uuid.length, 36);
      expect(
          uuid,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('should generate unique UUIDs', () {
      final uuids = List.generate(100, (_) => generateUuidV7());
      expect(uuids.toSet().length, 100);
    });

    test('should have consistent timestamp prefix ordering over time',
        () async {
      final uuid1 = generateUuidV7();
      await Future.delayed(const Duration(milliseconds: 2));
      final uuid2 = generateUuidV7();
      // UUIDs generated at different milliseconds should be ordered
      expect(uuid2.compareTo(uuid1), greaterThan(0));
    });
  });

  group('SimpleEventEmitter', () {
    test('should emit and receive events', () {
      final emitter = SimpleEventEmitter();
      String? received;
      emitter.on('test', (payload) => received = payload as String);
      emitter.emit('test', 'hello');
      expect(received, 'hello');
    });

    test('should support unsubscribe', () {
      final emitter = SimpleEventEmitter();
      var count = 0;
      final unsub = emitter.on('test', (_) => count++);
      emitter.emit('test', null);
      expect(count, 1);
      unsub();
      emitter.emit('test', null);
      expect(count, 1);
    });

    test('should support wildcard listeners', () {
      final emitter = SimpleEventEmitter();
      String? receivedEvent;
      emitter.on('*', (event, payload) => receivedEvent = event as String);
      emitter.emit('custom', 'data');
      expect(receivedEvent, 'custom');
    });
  });

  group('InMemoryStorage', () {
    test('should store and retrieve values', () {
      final storage = InMemoryStorage();
      storage.setProperty(PostHogPersistedProperty.distinctId, 'user-1');
      expect(storage.getProperty<String>(PostHogPersistedProperty.distinctId),
          'user-1');
    });

    test('should remove values when set to null', () {
      final storage = InMemoryStorage();
      storage.setProperty(PostHogPersistedProperty.distinctId, 'user-1');
      storage.setProperty(PostHogPersistedProperty.distinctId, null);
      expect(storage.getProperty<String>(PostHogPersistedProperty.distinctId),
          isNull);
    });
  });

  group('FeatureFlagUtils', () {
    test('should parse v2 flags response', () {
      final response = parseFlagsResponse({
        'flags': {
          'flag1': {
            'key': 'flag1',
            'enabled': true,
          },
          'flag2': {
            'key': 'flag2',
            'enabled': true,
            'variant': 'control',
            'metadata': {'payload': '"hello"'},
          },
        },
      });

      expect(response.featureFlags['flag1'], true);
      expect(response.featureFlags['flag2'], 'control');
      expect(response.flags['flag1']?.enabled, true);
      expect(response.flags['flag2']?.variant, 'control');
      expect(response.flags['flag2']?.enabled, true);
    });

    test('should derive featureFlagPayloads from flags', () {
      final response = parseFlagsResponse({
        'flags': {
          'flag1': {
            'key': 'flag1',
            'enabled': true,
            'metadata': {'payload': '{"key":"value"}'},
          },
          'flag2': {
            'key': 'flag2',
            'enabled': false,
            'metadata': {'payload': '"ignored"'},
          },
        },
      });

      expect(response.featureFlagPayloads['flag1'], {'key': 'value'});
      // flag2 is disabled so payload should not be included
      expect(response.featureFlagPayloads.containsKey('flag2'), false);
    });

    test('should get flag value from detail', () {
      expect(
        getFeatureFlagValue(
            const FeatureFlagDetail(key: 'test', enabled: true, variant: 'a')),
        'a',
      );
      expect(
        getFeatureFlagValue(
            const FeatureFlagDetail(key: 'test', enabled: true)),
        true,
      );
      expect(
        getFeatureFlagValue(
            const FeatureFlagDetail(key: 'test', enabled: false)),
        false,
      );
      expect(getFeatureFlagValue(null), isNull);
    });

    test('should parse payloads', () {
      expect(parsePayload('{"key":"value"}'), {'key': 'value'});
      expect(parsePayload('"hello"'), 'hello');
      expect(parsePayload(42), 42);
      expect(parsePayload('not-json{'), 'not-json{');
    });
  });

  group('Bootstrap', () {
    test('should bootstrap with feature flags', () {
      final storage = InMemoryStorage();
      final client = TestPostHogClient(
        'test-key',
        options: const PostHogCoreOptions(
          preloadFeatureFlags: false,
          bootstrap: BootstrapConfig(
            flags: {
              'flag1': FeatureFlagDetail(key: 'flag1', enabled: true),
              'flag2': FeatureFlagDetail(
                  key: 'flag2', enabled: true, variant: 'variant-a'),
            },
          ),
        ),
        storage: storage,
      );

      final details = client.getFeatureFlagDetails();
      expect(details?.flags['flag1']?.enabled, true);
      expect(details?.flags['flag2']?.variant, 'variant-a');
    });

    test('should bootstrap with distinct ID', () {
      final storage = InMemoryStorage();
      final client = TestPostHogClient(
        'test-key',
        options: const PostHogCoreOptions(
          preloadFeatureFlags: false,
          bootstrap: BootstrapConfig(
            distinctId: 'bootstrap-user',
            isIdentifiedId: true,
          ),
        ),
        storage: storage,
      );

      expect(client.getDistinctId(), 'bootstrap-user');
    });
  });
}
