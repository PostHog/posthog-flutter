import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/persistence.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  group('PostHogCore.capture', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage);
    });

    test('enqueues the event with its properties and library metadata', () {
      client.capture('test_event', properties: {'key': 'value'});

      expect(getQueue(storage), hasLength(1));
      expect(queuedMessage(storage, 0)['event'], 'test_event');
      final props = queuedProps(storage, 0);
      expect(props['key'], 'value');
      expect(props[r'$lib'], postHogFlutterSdkName);
    });

    test('keeps an anonymous user personless', () {
      client.capture('test_event');

      expect(queuedProps(storage, 0)[r'$process_person_profile'], isFalse);
      expect(queuedProps(storage, 0)[r'$is_identified'], isFalse);
    });

    for (final key in [r'$set', r'$set_once']) {
      test('person properties in $key make an anonymous user person-processed',
          () {
        client.capture('signed_up', properties: {
          key: {'plan': 'pro'},
        });
        client.capture('next_event');

        expect(queuedProps(storage, 0)[r'$process_person_profile'], isTrue,
            reason: 'sending person properties asks for a person profile');
        expect(queuedProps(storage, 1)[r'$process_person_profile'], isTrue);
      });
    }

    test('person properties stay personless when personProfiles is never', () {
      final storage = tempStorage();
      final client = testClient(server,
          config: testConfig(personProfiles: PostHogPersonProfiles.never),
          storage: storage);

      client.capture('signed_up', properties: {
        r'$set': {'plan': 'pro'},
      });

      expect(queuedProps(storage, 0)[r'$process_person_profile'], isFalse);
    });

    test(r'$groups apply to that event only', () async {
      final reloads = await flagsRequestsFor(client, server, () {
        client.capture('invite_sent', properties: {
          r'$groups': {'company': 'acme'},
        });
        client.capture('next_event');
      });

      expect(queuedProps(storage, 0)[r'$groups'], {'company': 'acme'});
      expect(queuedProps(storage, 1).containsKey(r'$groups'), isFalse);
      expect(queuedProps(storage, 1)[r'$process_person_profile'], isFalse);
      expect(reloads, 0, reason: 'an event-level group is not a group change');
    });

    test('attaches the session debug properties', () async {
      final storage = tempStorage();
      final before = DateTime.now().millisecondsSinceEpoch;
      final client = testClient(server, storage: storage);
      final after = DateTime.now().millisecondsSinceEpoch;
      // Real wait: the session starts with the client, not its first event.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      client.capture('first');
      client.register({r'$sdk_debug_pending_queue_size': 'registered'});
      client.capture('second');

      final first = queuedProps(storage, 0);
      expect(first[r'$sdk_debug_session_start'],
          allOf(greaterThanOrEqualTo(before), lessThanOrEqualTo(after)));
      expect(first[r'$sdk_debug_current_session_duration'],
          greaterThanOrEqualTo(10));
      expect(first[r'$sdk_debug_pending_queue_size'], 0);
      expect(queuedProps(storage, 1)[r'$sdk_debug_pending_queue_size'], 1,
          reason: 'SDK debug values win over a registered super property');
    });
  });

  group('PostHogCore.getDistinctId', () {
    test('is an anonymous id, generated once and kept across restarts', () {
      final dir = tempDirectory();
      final first = testClient(server, storage: FileStorage(dir.path));
      final anonymousId = first.getDistinctId();
      first.close();

      final restarted = testClient(server, storage: FileStorage(dir.path));

      expect(anonymousId, isNotEmpty);
      expect(restarted.getDistinctId(), anonymousId);
    });
  });

  group('PostHogCore.identify', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage);
    });

    test('switches the distinct id and marks the person identified', () {
      client.identify('user-123');

      expect(client.getDistinctId(), 'user-123');
      expect(storage.getProperty<String>(PostHogPersistedProperty.personMode),
          'identified');
    });

    test('is ignored when personProfiles is never', () {
      final client = testClient(server,
          config: testConfig(personProfiles: PostHogPersonProfiles.never));

      client.identify('user-123');

      expect(client.getDistinctId(), isNot('user-123'));
    });

    for (final distinctId in ['', '   ']) {
      test('ignores the blank distinct id "$distinctId"', () async {
        final anonymousId = client.getDistinctId();

        final reloads = await flagsRequestsFor(
            client, server, () => client.identify(distinctId));

        expect(client.getDistinctId(), anonymousId);
        expect(getQueue(storage), isEmpty);
        expect(reloads, 0);
      });
    }

    test(r'sends $identify linking the anonymous id, and reloads flags',
        () async {
      final anonymousId = client.getDistinctId();

      final reloads = await flagsRequestsFor(client, server,
          () => client.identify('user-123', userProperties: {'plan': 'pro'}));

      expect(queuedEvents(storage), [r'$identify']);
      expect(queuedMessage(storage, 0)['distinct_id'], 'user-123');
      final props = queuedProps(storage, 0);
      expect(props['distinct_id'], 'user-123');
      expect(props[r'$anon_distinct_id'], anonymousId);
      expect(props[r'$set'], {'plan': 'pro'});
      expect(reloads, 1);
    });

    test(r'with the anonymous id marks the user identified with a $set',
        () async {
      final anonymousId = client.getDistinctId();

      final reloads = await flagsRequestsFor(
          client, server, () => client.identify(anonymousId));

      expect(queuedEvents(storage), [r'$set'],
          reason: r'there is no anonymous history to link, so no $identify');
      expect(queuedProps(storage, 0)[r'$is_identified'], isTrue);
      expect(queuedProps(storage, 0)[r'$process_person_profile'], isTrue);
      expect(reloads, 0,
          reason: 'the identified state alone does not affect flags');
    });

    test('with the anonymous id and properties reloads flags', () async {
      final reloads = await flagsRequestsFor(
          client,
          server,
          () => client.identify(client.getDistinctId(),
              userProperties: {'plan': 'pro'}));

      expect(queuedProps(storage, 0)[r'$set'], {'plan': 'pro'});
      expect(reloads, 1);
    });

    test(r'with the same id sends new properties once, without reloading flags',
        () async {
      client.identify('user-123');

      final reloads = await flagsRequestsFor(client, server, () {
        for (var i = 0; i < 2; i++) {
          client.identify('user-123', userProperties: {'plan': 'pro'});
        }
      });

      expect(queuedEvents(storage), [r'$identify', r'$set']);
      expect(
          storage.getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.personProperties),
          {'plan': 'pro'});
      expect(reloads, 0);
    });

    test('with the same id and no properties sends nothing', () {
      client.identify('user-123');

      client.identify('user-123');

      expect(queuedEvents(storage), [r'$identify']);
    });

    test('with another id while identified keeps the identified user',
        () async {
      client.identify('user-123');

      final reloads = await flagsRequestsFor(
          client, server, () => client.identify('user-456'));

      expect(client.getDistinctId(), 'user-123');
      expect(queuedEvents(storage), [r'$identify']);
      expect(reloads, 0);
    });
  });

  group('Person processing hints', () {
    test(r'are on $identify, $create_alias and $groupidentify', () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);

      client.identify('user-123');
      client.alias('user-alias');
      client.group('company', 'acme');

      for (final event in [r'$identify', r'$create_alias', r'$groupidentify']) {
        final props = queuedPropsOf(storage, event);
        expect(props[r'$process_person_profile'], isTrue, reason: event);
        expect(props[r'$is_identified'], isTrue, reason: event);
        expect(props, contains(r'$sdk_debug_session_start'), reason: event);
      }
    });
  });

  group('PostHogCore.reset', () {
    test('clears identity but keeps the queue', () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      client.identify('user-123');
      client.capture('test_event');

      client.reset();

      expect(client.getDistinctId(), isNot('user-123'));
      expect(storage.getProperty<String>(PostHogPersistedProperty.personMode),
          isNull);
      expect(getQueue(storage), isNotEmpty,
          reason: 'reset clears identity, not pending events');
    });

    test('starts a new session', () {
      final client = testClient(server);
      final sessionId = client.getSessionId();

      client.reset();

      expect(client.getSessionId(), isNot(sessionId));
    });
  });

  group('PostHogCore.getSessionId', () {
    test('reuses the session id within the expiration window', () {
      final client = testClient(server);
      final sessionId = client.getSessionId();

      expect(sessionId, isNotEmpty);
      expect(client.getSessionId(), sessionId);
    });

    test('starts a new session for every client', () {
      final dir = tempDirectory();
      final first = testClient(server, storage: FileStorage(dir.path));
      final sessionId = first.getSessionId();
      first.close();

      final second = testClient(server, storage: FileStorage(dir.path));

      expect(second.getSessionId(), isNot(sessionId),
          reason: 'an app start begins a new session');
    });
  });

  group('PostHogCore.debug', () {
    test('logs every queued event until turned off', () {
      final client = testClient(server);

      client.debug(true);
      final lines = printedLines(() => client.capture('sign_in'));
      client.debug(false);

      expect(lines, contains(allOf(contains('capture'), contains('sign_in'))));
      expect(printedLines(() => client.capture('sign_out')), isEmpty);
    });
  });

  group('Super properties', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage);
    });

    test('registered properties are attached to captured events', () {
      client.register({'app_version': '1.0.0'});

      client.capture('test_event');

      expect(queuedProps(storage, 0)['app_version'], '1.0.0');
    });

    test('unregistered properties stop being attached', () {
      client.register({'app_version': '1.0.0', 'platform': 'web'});

      client.unregister('app_version');
      client.capture('test_event');

      final props = queuedProps(storage, 0);
      expect(props['app_version'], isNull);
      expect(props['platform'], 'web');
    });

    test("an event's own value wins over a registered one", () {
      client.register({'plan': 'free'});

      client.capture('test_event', properties: {'plan': 'pro'});

      expect(queuedProps(storage, 0)['plan'], 'pro');
    });
  });

  group('PostHogCore.registerForSession', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage);
    });

    test("win over registered properties, not over the event's own", () {
      client.register({'screen': 'registered', 'plan': 'free'});
      client.registerForSession({'screen': 'Checkout', 'plan': 'trial'});

      client.capture('first');
      client.capture('second', properties: {'plan': 'pro'});

      expect(queuedProps(storage, 0)['screen'], 'Checkout');
      expect(queuedProps(storage, 0)['plan'], 'trial');
      expect(queuedProps(storage, 1)['plan'], 'pro');
    });

    test('are dropped by reset', () {
      client.registerForSession({'screen': 'Checkout'});

      client.reset();
      client.capture('after reset');

      expect(queuedProps(storage, 0), isNot(contains('screen')));
    });
  });

  group('PostHogCore.setPersonPropertiesForFlags', () {
    test('merges consecutive calls instead of replacing', () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);

      client.setPersonPropertiesForFlags({'role': 'admin'});
      client.setPersonPropertiesForFlags({'plan': 'pro'});

      expect(
          storage.getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.personProperties),
          {'role': 'admin', 'plan': 'pro'});
    });
  });

  group('PostHogCore.alias', () {
    test(r'captures a $create_alias event carrying the alias', () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);

      client.alias('new-alias');

      expect(queuedMessage(storage, 0)['event'], r'$create_alias');
      expect(queuedProps(storage, 0)['alias'], 'new-alias');
    });

    for (final alias in ['', '   ']) {
      test('ignores the empty alias "$alias" with a warning', () {
        final storage = tempStorage();
        final client = testClient(server,
            config: testConfig(debug: true), storage: storage);

        final lines = printedLines(() => client.alias(alias));
        client.capture('next_event');

        expect(queuedEvents(storage), ['next_event']);
        expect(queuedProps(storage, 0)[r'$process_person_profile'], isFalse,
            reason: 'an ignored alias does not turn on person processing');
        expect(lines, contains(contains('empty alias')));
      });
    }
  });

  group('PostHogCore.group', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage);
    });

    test(r'captures a $groupidentify event with the group properties', () {
      client.group('company', 'company-123', groupProperties: {'name': 'Acme'});

      final props = queuedPropsOf(storage, r'$groupidentify');
      expect(props[r'$group_type'], 'company');
      expect(props[r'$group_key'], 'company-123');
      expect(props[r'$group_set'], {'name': 'Acme'});
    });

    test(r'captures $groupidentify without group properties too', () {
      client.group('company', 'company-123');

      final props = queuedPropsOf(storage, r'$groupidentify');
      expect(props[r'$group_type'], 'company');
      expect(props[r'$group_key'], 'company-123');
    });

    test('group properties reach the flags reload of a group change', () async {
      client.group('company', 'company-123', groupProperties: {'seats': 50});

      final body = await server.waitForFlagsRequest(0);
      expect(body['groups'], {'company': 'company-123'});
      expect(body['group_properties'], {
        'company': {'seats': 50},
      });
    });

    test('the same group key again does not reload flags', () async {
      final reloads = await flagsRequestsFor(client, server, () {
        client.group('company', 'company-123');
        client.group('company', 'company-123', groupProperties: {'seats': 50});
      });

      expect(queuedEvents(storage), [r'$groupidentify', r'$groupidentify']);
      expect(reloads, 1);
      expect(
          storage.getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.groupProperties),
          {
            'company': {'seats': 50},
          });
    });

    // (group type, group key)
    const emptyGroups = <(String, String)>[
      ('', 'company-123'),
      ('company', ''),
      ('   ', 'company-123'),
    ];

    for (final (groupType, groupKey) in emptyGroups) {
      test('ignores the group "$groupType" "$groupKey" with a warning',
          () async {
        final storage = tempStorage();
        final client = testClient(server,
            config: testConfig(debug: true), storage: storage);

        late List<String> lines;
        final reloads = await flagsRequestsFor(client, server, () {
          lines = printedLines(() => client
              .group(groupType, groupKey, groupProperties: {'seats': 50}));
        });
        client.capture('next_event');

        expect(queuedEvents(storage), ['next_event']);
        expect(queuedProps(storage, 0), isNot(contains(r'$groups')));
        expect(
            storage
                .getProperty<Object>(PostHogPersistedProperty.groupProperties),
            isNull);
        expect(reloads, 0);
        expect(lines, contains(contains('empty group type or key')));
      });
    }
  });

  group('Property serialization', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client =
          testClient(server, config: testConfig(debug: true), storage: storage);
    });

    test('drops null-valued object members, keeping array positions', () {
      // The example of the capture spec.
      client.capture('Nullable Properties',
          properties: jsonDecode('{"test":null,"nested":{"drop":null},'
              '"items":["1",null,2,{"drop":null},[null]],"empty":"",'
              '"zero":0,"enabled":false,"literal":"null","emptyArray":[]}'));

      final props = queuedProps(storage, 0);
      expect(props, isNot(contains('test')));
      expect(props['nested'], <String, Object?>{});
      expect(props['items'], [
        '1',
        null,
        2,
        <String, Object?>{},
        [null],
      ]);
      expect(props['empty'], '');
      expect(props['zero'], 0);
      expect(props['enabled'], isFalse);
      expect(props['literal'], 'null');
      expect(props['emptyArray'], isEmpty);
    });

    test('converts the values JSON cannot represent', () {
      final at = DateTime.utc(2024, 5, 6, 7, 8, 9);

      client.capture('evt', properties: {
        'at': at,
        'local_at': at.toLocal(),
        'link': Uri.parse('https://posthog.com/docs'),
        'plan': const _Plan('pro'),
        'ratio': double.nan,
        'counts': {1: 'one'},
      });

      final props = queuedProps(storage, 0);
      expect(props['at'], '2024-05-06T07:08:09.000Z');
      expect(props['local_at'], '2024-05-06T07:08:09.000Z');
      expect(props['link'], 'https://posthog.com/docs');
      expect(props['plan'], {'name': 'pro'},
          reason: 'jsonEncode supports toJson(), so the event must too');
      expect(props['ratio'], 'NaN');
      expect(props['counts'], {'1': 'one'});
      expect(() => jsonEncode(getQueue(storage)), returnsNormally);
    });

    test('sends a value without a JSON form as its string, with a warning', () {
      final lines = printedLines(() => client
          .capture('evt', properties: {'timeout': const Duration(seconds: 3)}));

      expect(queuedProps(storage, 0)['timeout'], '0:00:03.000000');
      expect(lines, contains(contains('Duration')));
    });

    test('a map that contains itself does not break the capture', () {
      final cyclic = <String, Object?>{'name': 'loop'};
      cyclic['self'] = cyclic;

      expect(() => client.capture('evt', properties: {'cyclic': cyclic}),
          returnsNormally);

      final sent = queuedProps(storage, 0)['cyclic'] as Map<String, Object?>;
      expect(sent['name'], 'loop');
      expect(sent['self'], isA<String>());
    });

    test('a super property and an event holding a DateTime are stored', () {
      final dir = tempDirectory();
      final storage = FileStorage(dir.path);
      final client = testClient(server, storage: storage);

      client.register({'since': DateTime.utc(2024)});
      client.capture('evt', properties: {'at': DateTime.utc(2024, 2)});

      expect(
          FileStorage(dir.path).getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.props),
          {'since': '2024-01-01T00:00:00.000Z'});
      // Read back from its file.
      expect(queuedProps(storage, 0)['at'], '2024-02-01T00:00:00.000Z');
    });
  });

  group('Input tolerance', () {
    // User-supplied maps arrive loosely typed or straight from jsonDecode;
    // neither shape may throw or lose the event.
    final cases = <(String, void Function(DesktopPostHog client))>[
      (
        r'capture with jsonDecode properties including $groups',
        (client) => client.capture('evt',
            properties: jsonDecode('{"\$groups": {"team": "core"}, "n": 1}')
                as Map<String, Object?>),
      ),
      (
        'setPersonProperties with a nested empty map',
        (client) =>
            client.setPersonProperties(userPropertiesToSet: {'meta': {}}),
      ),
    ];

    for (final (description, act) in cases) {
      test('$description enqueues without throwing', () {
        final storage = tempStorage();
        final client = testClient(server, storage: storage);

        expect(() => act(client), returnsNormally);
        expect(getQueue(storage), isNotEmpty);
      });
    }
  });
}

class _Plan {
  const _Plan(this.name);

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}
