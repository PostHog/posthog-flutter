import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/persistence.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  group('Opt-out consent', () {
    test('optOut: true blocks events until optIn()', () {
      final storage = tempStorage();
      final client = testClient(server,
          config: testConfig(optOut: true), storage: storage);

      client.capture('evt');

      expect(getQueue(storage), isEmpty);
      expect(client.optedOut, isTrue);
    });

    test('optIn() re-enables a client created with optOut: true', () {
      final storage = tempStorage();
      final client = testClient(server,
          config: testConfig(optOut: true), storage: storage);

      client.optIn();
      client.capture('evt');

      expect(client.optedOut, isFalse);
      expect(getQueue(storage), hasLength(1));
    });

    test('reset() keeps an opt-out for this client, not the next one', () {
      final dir = tempDirectory();
      final storage = FileStorage(dir.path);
      final client = testClient(server, storage: storage);

      client.optOut();
      client.reset();

      expect(client.optedOut, isTrue,
          reason: 'a logout must not silently re-enable tracking');
      client.capture('evt');
      expect(getQueue(storage), isEmpty);

      client.close();
      final restarted = testClient(server, storage: FileStorage(dir.path));
      expect(restarted.optedOut, isFalse,
          reason: 'reset clears the persisted decision, so the next client '
              'starts from the configured default');
    });

    test('reset() keeps an opt-in for this client, not the next one', () {
      final dir = tempDirectory();
      final storage = FileStorage(dir.path);
      final client = testClient(server,
          config: testConfig(optOut: true), storage: storage);

      client.optIn();
      client.reset();
      client.capture('evt');

      expect(getQueue(storage), hasLength(1));
      client.close();
      final restarted = testClient(server,
          config: testConfig(optOut: true), storage: FileStorage(dir.path));
      expect(restarted.optedOut, isTrue);
    });

    test('consent fails closed while the store is unreadable', () {
      final dir = Directory.systemTemp.createTempSync('posthog_consent');
      final dataFile = '${dir.path}/posthog_data.json';
      addTearDown(() {
        chmod('644', dataFile);
        dir.deleteSync(recursive: true);
      });
      FileStorage(dir.path)
        ..setProperty(PostHogPersistedProperty.anonymousId, 'stored-anon')
        ..close();
      chmod('000', dataFile);
      final storage = FileStorage(dir.path);
      final client =
          testClient(server, config: testConfig(debug: true), storage: storage);

      client.capture('before opt-in');
      expect(getQueue(storage), isEmpty,
          reason: 'with consent unknown, tracking without it would be worse '
              'than dropping events');

      chmod('644', dataFile);
      expect(storage.isDegraded, isTrue);
      client.capture('after disk recovery');
      expect(getQueue(storage), isEmpty,
          reason: 'a recovered file cannot retroactively establish consent '
              'for an instance that never read its snapshot');

      final lines = printedLines(() {
        client.optIn();
        client.capture('first');
        client.capture('second');
      });

      expect(lines, contains(contains('"opted_out" in memory only')));
      expect(queuedEvents(storage), ['first', 'second'],
          reason: 'an explicit opt-in applies although it cannot be stored');
      expect(queuedMessage(storage, 1)['distinct_id'],
          queuedMessage(storage, 0)['distinct_id']);
      final stored = FileStorage(dir.path);
      expect(stored.getProperty<String>(PostHogPersistedProperty.anonymousId),
          'stored-anon');
      expect(
          stored.getProperty<bool>(PostHogPersistedProperty.optedOut), isNull);
    }, skip: chmodSkip);

    test('a consent decision outlasts the storage becoming readable', () {
      final dir = Directory.systemTemp.createTempSync('posthog_consent');
      final dataFile = '${dir.path}/posthog_data.json';
      addTearDown(() {
        chmod('644', dataFile);
        dir.deleteSync(recursive: true);
      });
      FileStorage(dir.path)
        ..setProperty(PostHogPersistedProperty.optedOut, false)
        ..close();
      chmod('000', dataFile);
      final client = testClient(server, storage: FileStorage(dir.path));

      client.optOut();
      chmod('644', dataFile);

      expect(client.optedOut, isTrue,
          reason: 'the opt-out made while the file could not be read wins '
              'over the stored opt-in');
    }, skip: chmodSkip);

    test('identity set while storage is unreadable survives disk recovery', () {
      final dir = Directory.systemTemp.createTempSync('posthog_identity');
      final dataFile = '${dir.path}/posthog_data.json';
      addTearDown(() {
        chmod('644', dataFile);
        dir.deleteSync(recursive: true);
      });
      FileStorage(dir.path)
        ..setProperty(PostHogPersistedProperty.anonymousId, 'alice-anon')
        ..setProperty(PostHogPersistedProperty.distinctId, 'alice')
        ..setProperty(PostHogPersistedProperty.personMode, 'identified')
        ..setProperty(PostHogPersistedProperty.optedOut, true)
        ..close();
      final originalSnapshot = File(dataFile).readAsStringSync();
      chmod('000', dataFile);
      final storage = FileStorage(dir.path);
      final client = testClient(server, storage: storage);

      expect(client.optedOut, isTrue);
      client.optIn();
      client.identify('bob');
      expect(client.getDistinctId(), 'bob');

      chmod('644', dataFile);
      client.capture('after recovery');

      expect(client.getDistinctId(), 'bob');
      expect(client.optedOut, isFalse);
      final recoveredEvent = getQueue(storage)
          .singleWhere((message) => message['event'] == 'after recovery');
      expect(recoveredEvent['distinct_id'], 'bob');
      expect(File(dataFile).readAsStringSync(), originalSnapshot);

      client.close();
      final restarted = FileStorage(dir.path);
      addTearDown(restarted.close);
      expect(restarted.getProperty<String>(PostHogPersistedProperty.distinctId),
          'alice');
      expect(restarted.getProperty<String>(PostHogPersistedProperty.personMode),
          'identified');
      expect(restarted.getProperty<bool>(PostHogPersistedProperty.optedOut),
          isTrue);
    }, skip: chmodSkip);

    test('reset while storage is unreadable stays cleared after recovery', () {
      final dir = Directory.systemTemp.createTempSync('posthog_reset');
      final dataFile = '${dir.path}/posthog_data.json';
      addTearDown(() {
        chmod('644', dataFile);
        dir.deleteSync(recursive: true);
      });
      FileStorage(dir.path)
        ..setProperty(PostHogPersistedProperty.anonymousId, 'alice-anon')
        ..setProperty(PostHogPersistedProperty.distinctId, 'alice')
        ..setProperty(PostHogPersistedProperty.personMode, 'identified')
        ..setProperty(PostHogPersistedProperty.props, {'plan': 'old'})
        ..setProperty(PostHogPersistedProperty.featureFlagDetails, {
          'flags': {
            'old-flag': {'key': 'old-flag', 'enabled': true},
          },
        })
        ..close();
      chmod('000', dataFile);
      final storage = FileStorage(dir.path);
      final client = testClient(server, storage: storage);

      client.optIn();
      client.reset();
      final resetDistinctId = client.getDistinctId();
      chmod('644', dataFile);

      expect(client.getDistinctId(), resetDistinctId);
      expect(client.getDistinctId(), isNot('alice'));
      expect(
          storage.getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.props),
          isNull);
      expect(
          storage.getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.featureFlagDetails),
          isNull);
    }, skip: chmodSkip);
  });

  group('Calls while opted out', () {
    late FileStorage storage;
    late DesktopPostHog client;

    setUp(() {
      storage = tempStorage();
      client = testClient(server, storage: storage);
      client.optOut();
    });

    test('identify, alias and group leave the identity untouched', () async {
      final anonymousId = client.getDistinctId();

      final reloads = await flagsRequestsFor(client, server, () {
        client.identify('user-123', userProperties: {'plan': 'pro'});
        client.alias('user-alias');
        client.group('company', 'acme', groupProperties: {'seats': 50});
      });

      expect(client.getDistinctId(), anonymousId);
      for (final key in [
        PostHogPersistedProperty.personMode,
        PostHogPersistedProperty.enablePersonProcessing,
        PostHogPersistedProperty.props,
        PostHogPersistedProperty.personProperties,
        PostHogPersistedProperty.groupProperties,
      ]) {
        expect(storage.getProperty<Object>(key), isNull, reason: key.key);
      }
      expect(reloads, 0);
    });

    test('capture leaves the person state untouched', () {
      client.capture('evt', properties: {
        r'$set': {'plan': 'pro'},
      });

      expect(
          storage.getProperty<bool>(
              PostHogPersistedProperty.enablePersonProcessing),
          isNull);
      expect(
          storage.getProperty<Map<String, Object?>>(
              PostHogPersistedProperty.personProperties),
          isNull);
    });

    test('setPersonProperties is not remembered as sent', () async {
      final reloads = await flagsRequestsFor(
          client,
          server,
          () =>
              client.setPersonProperties(userPropertiesToSet: {'plan': 'pro'}));
      expect(reloads, 0);

      client.optIn();
      client.setPersonProperties(userPropertiesToSet: {'plan': 'pro'});

      expect(queuedEvents(storage), [r'$set'],
          reason: 'the dropped call must not count as a duplicate');
    });
  });
}
