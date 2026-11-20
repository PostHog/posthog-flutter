import 'package:flutter_test/flutter_test.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  group('Context properties', () {
    test('attached to every captured event', () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage, context: _context);

      client.capture('event', properties: {'foo': 'bar'});

      final props = queuedProps(storage, 0);
      expect(props[r'$os_name'], 'TestOS');
      expect(props[r'$app_version'], '1.0.0');
      expect(props['foo'], 'bar');
    });

    test('lose to super properties and event properties', () {
      final storage = tempStorage();
      final client = testClient(server,
          storage: storage, context: _context, timezone: 'Europe/Berlin');

      client.register({r'$os_name': 'FromSuperProps'});
      client.capture('event', properties: {
        r'$app_version': '2.0.0',
        r'$timezone': 'UTC',
        r'$lib': 'custom',
      });

      final props = queuedProps(storage, 0);
      expect(props[r'$os_name'], 'FromSuperProps');
      expect(props[r'$app_version'], '2.0.0');
      expect(props[r'$timezone'], 'UTC');
      expect(props[r'$lib'], 'custom');
    });

    test('absent by default', () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);

      client.capture('event');

      expect(queuedProps(storage, 0).containsKey(r'$os_name'), isFalse);
      expect(queuedProps(storage, 0).containsKey(r'$timezone'), isFalse);
    });

    test(r'carry the $timezone a host provides', () {
      final storage = tempStorage();
      final client =
          testClient(server, storage: storage, timezone: 'Europe/Berlin');

      client.capture('event');

      expect(queuedProps(storage, 0)[r'$timezone'], 'Europe/Berlin');
    });
  });
}

const _context = <String, Object?>{
  r'$os_name': 'TestOS',
  r'$app_version': '1.0.0',
};
