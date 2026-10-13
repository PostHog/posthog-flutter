import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  for (final invalidGroups in <Object>[
    'legacy',
    42,
    ['legacy'],
  ]) {
    test('invalid groups $invalidGroups do not block capture and flags',
        () async {
      final directory = tempDirectory();
      final first = testClient(server, storage: FileStorage(directory.path));
      first.register({r'$groups': invalidGroups, 'plan': 'pro'});
      first.close();
      final client = testClient(server, storage: FileStorage(directory.path));

      client.capture('purchase');
      await client.reloadFeatureFlagsAsync();
      await client.flush();

      final properties = server.events.single['properties']! as Map;
      expect(properties['plan'], 'pro');
      expect(properties[r'$process_person_profile'], isFalse);
      expect(server.flagsRequests.last.body['groups'], isEmpty);

      client.group('company', 'acme');
      await client.reloadFeatureFlagsAsync();
      expect(server.flagsRequests.last.body['groups'], {'company': 'acme'});
    });
  }

  test('valid memberships in an old store survive an invalid neighboring key',
      () async {
    final directory = tempDirectory();
    final first = testClient(server, storage: FileStorage(directory.path));
    first.register({
      r'$groups': {'company': 'acme', 'broken': 42},
    });
    first.close();
    final storage = FileStorage(directory.path);
    final client = testClient(server, storage: storage);

    client.capture('purchase');
    await client.reloadFeatureFlagsAsync();

    expect(queuedProps(storage, 0)[r'$process_person_profile'], isTrue);
    expect(server.flagsRequests.last.body['groups'], {'company': 'acme'});
  });

  test('a caller session ID applies only to its event', () {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    final internalSession = client.getSessionId();

    client
        .capture('external', properties: {r'$session_id': 'external-session'});
    client.capture('internal');

    expect(queuedProps(storage, 0)[r'$session_id'], 'external-session');
    expect(queuedProps(storage, 1)[r'$session_id'], internalSession);
    expect(client.getSessionId(), internalSession);
  });

  for (final invalidSession in <Object>['', 42]) {
    test('invalid session ID $invalidSession is replaced with the current ID',
        () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      client.capture('purchase', properties: {r'$session_id': invalidSession});
      expect(queuedProps(storage, 0)[r'$session_id'], client.getSessionId());
    });
  }

  for (final property in [r'$set', r'$set_once']) {
    test('a direct $property updates the marker for the latest person update',
        () async {
      final client = testClient(server);
      void setPlan(String plan) {
        if (property == r'$set') {
          client.setPersonProperties(userPropertiesToSet: {'plan': plan});
        } else {
          client.setPersonProperties(userPropertiesToSetOnce: {'plan': plan});
        }
      }

      setPlan('A');
      client.capture(r'$set', properties: {
        property: {'plan': 'B'},
      });
      setPlan('A');
      await client.flush();

      expect(
        [
          for (final event in server.events)
            ((event['properties']! as Map)[property] as Map)['plan'],
        ],
        ['A', 'B', 'A'],
      );
    });
  }

  test('a direct set with the same properties suppresses the next duplicate',
      () {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    client.capture(r'$set', properties: {
      r'$set': {'plan': 'A'},
    });
    client.setPersonProperties(userPropertiesToSet: {'plan': 'A'});
    expect(queuedEvents(storage), [r'$set']);
  });

  test('opt-out does not update the marker for the latest person update', () {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    client.setPersonProperties(userPropertiesToSet: {'plan': 'A'});
    client.optOut();
    client.capture(r'$set', properties: {
      r'$set': {'plan': 'B'},
    });
    client.optIn();
    client.setPersonProperties(userPropertiesToSet: {'plan': 'A'});
    expect(queuedEvents(storage), [r'$set']);
  });

  test('null person properties do not break duplicate suppression', () {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    client.setPersonProperties(userPropertiesToSet: {'plan': 'A', 'old': null});
    client.setPersonProperties(userPropertiesToSet: {'plan': 'A', 'old': null});
    expect(queuedEvents(storage), [r'$set']);
  });

  test('event properties take precedence over registered properties', () {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    client.register({'plan': 'pro'});
    client.capture('purchase', properties: {'plan': 'free'});
    expect(queuedProps(storage, 0)['plan'], 'free');
  });

  test(
      'session properties take precedence after caller properties and before registered properties',
      () {
    final storage = tempStorage();
    final client = testClient(server, storage: storage);
    client.register({'plan': 'registered', 'screen': 'registered'});
    client.registerForSession({'plan': 'session', 'screen': 'Checkout'});
    client.capture('purchase', properties: {'plan': 'event'});
    expect(queuedProps(storage, 0)['plan'], 'event');
    expect(queuedProps(storage, 0)['screen'], 'Checkout');
  });
}
