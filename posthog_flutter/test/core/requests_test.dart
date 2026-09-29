import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/posthog_core_stateless.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  group('Requests to PostHog', () {
    test('post gzip-compressed JSON with the SDK as the user agent', () async {
      final client = testClient(server);

      client.capture('desktop_event', properties: {'source': 'test'});
      await client.flush();

      final request = server.batchRequests.single;
      expect(request.headers['content-encoding'], 'gzip');
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['user-agent'],
          '$postHogFlutterSdkName/$postHogFlutterVersion');
      expect(request.body['api_key'], 'k');
      expect(request.eventNames, ['desktop_event']);
    });

    test('report an error status together with the response body', () async {
      final client = testClient(server);
      server.respond = (_) =>
          const PostHogResponse(HttpStatus.badRequest, body: 'invalid batch');

      client.capture('evt');

      await expectLater(
          client.flush(),
          throwsA(isA<PostHogFetchHttpError>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.responseBody, 'responseBody', 'invalid batch')));
    });

    test('leave a redirect unfollowed', () async {
      final target = await LocalPostHogServer.start();
      final client = testClient(server);
      server.respond = (_) => PostHogResponse(HttpStatus.seeOther,
          location: '${target.url}/flags/?v=2&config=true');

      // A /flags request is not retried after a redirect, unlike a batch.
      await client.reloadFeatureFlagsAsync();

      expect(server.flagsRequests, hasLength(1));
      expect(target.requests, isEmpty);
    });

    test('respects HTTP Retry-After without waiting inside flush', () async {
      final client = testClient(server);
      server.respond = (_) => const PostHogResponse(HttpStatus.tooManyRequests,
          headers: {'Retry-After': '120'});
      client.capture('event');

      await expectLater(client.flush().timeout(const Duration(seconds: 2)),
          throwsA(isA<PostHogFetchHttpError>()));
      await client.flush();

      expect(server.batchRequests, hasLength(1));
    });

    test('report a refused connection as a connection error', () async {
      final closed = await LocalPostHogServer.start();
      await closed.close();
      final storage = tempStorage();
      final client = testClient(closed, storage: storage);

      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      expect(
          queuedPropsOf(
              storage, r'$feature_flag_called')[r'$feature_flag_error'],
          'connection_error');
    });
  });
}
