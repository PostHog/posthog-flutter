import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/persistence.dart';
import 'package:posthog_flutter/src/core/posthog_core_stateless.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  group('PostHogCore.flush', () {
    late LocalPostHogServer server;

    setUp(() async {
      server = await LocalPostHogServer.start();
    });

    test('sends queued events in one batch and empties the queue', () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);

      client.capture('sign_in');
      client.capture('sign_out');
      await client.flush();

      expect(server.batchRequests.single.eventNames, ['sign_in', 'sign_out']);
      expect(getQueue(storage), isEmpty);
    });

    test('removes sent events by identity when the queue head shifts',
        () async {
      final storage = tempStorage();
      final client = testClient(server,
          config: testConfig(flushAt: 2, maxBatchSize: 2, maxQueueSize: 2),
          storage: storage);

      final inFlight = Completer<void>();
      final release = Completer<void>();
      server.respond = (request) async {
        if (!inFlight.isCompleted) {
          inFlight.complete();
          await release.future;
        }
        return const PostHogResponse(HttpStatus.ok);
      };

      client.capture('first');
      client.capture('second'); // reaches flushAt, the batch takes off
      await inFlight.future;
      // Overflow while the batch is in flight: 'first' is evicted, so the
      // batch and the queue no longer line up positionally.
      client.capture('third');
      release.complete();
      await client.flush();

      expect(
        [for (final request in server.batchRequests) request.eventNames],
        [
          ['first', 'second'],
          ['third'],
        ],
        reason: "removal must match by uuid: positional removal would delete "
            "'third' from the queue instead of the already-evicted 'first'",
      );
      expect(getQueue(storage), isEmpty);
    });

    test('halves the batch size on HTTP 413 until the server accepts',
        () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      // This server rejects anything bigger than two events per request.
      server.respond = (request) => PostHogResponse(request.events.length > 2
          ? HttpStatus.requestEntityTooLarge
          : HttpStatus.ok);

      for (var i = 0; i < 8; i++) {
        client.capture('event_$i');
      }
      await client.flush();

      final batches = [
        for (final request in server.batchRequests) request.eventNames,
      ];
      expect(batches.map((batch) => batch.length).toList(), [8, 4, 2, 2, 2, 2]);
      expect(batches.skip(2).expand((batch) => batch).toList(),
          [for (var i = 0; i < 8; i++) 'event_$i']);
      expect(getQueue(storage), isEmpty);
    });

    test('shares one network cycle between concurrent calls', () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      final release = Completer<void>();
      server.respond = (request) async {
        await release.future;
        return const PostHogResponse(HttpStatus.ok);
      };

      client.capture('evt');
      final first = client.flush();
      final second = client.flush();
      release.complete();
      await Future.wait([first, second]);

      expect(server.batchRequests, hasLength(1));
      expect(getQueue(storage), isEmpty);
    });

    test('hard HTTP 400 is not retried and drops the batch', () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (_) => const PostHogResponse(HttpStatus.badRequest);

      client.capture('evt');
      await expectLater(client.flush(), throwsA(isA<PostHogFetchHttpError>()));

      expect(server.batchRequests, hasLength(1));
      expect(getQueue(storage), isEmpty);
    });

    test('retries a transient failure three times, three seconds apart', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.serviceUnavailable);
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api, storage: storage);
        Object? error;

        client.capture('evt');
        client.flush().catchError((Object e) {
          error = e;
        });

        async.elapse(Duration.zero);
        expect(api.batchRequests, hasLength(1));
        for (final attempts in [2, 3, 4]) {
          async.elapse(const Duration(milliseconds: 2999));
          expect(api.batchRequests, hasLength(attempts - 1));
          async.elapse(const Duration(milliseconds: 1));
          expect(api.batchRequests, hasLength(attempts));
        }
        expect(error, isA<PostHogFetchHttpError>());
        expect(getQueue(storage), hasLength(1));
      });
    });

    // (status, reason the batch stays queued)
    const transientStatuses = <(int, String)>[
      (408, 'the server timed out'),
      (429, 'the server asks to slow down'),
      (500, 'the server failed'),
      (
        301,
        'a POST redirect is not followed, so the batch never reached '
            'ingestion'
      ),
      (
        307,
        'a POST redirect is not followed, so the batch never reached '
            'ingestion'
      ),
    ];

    for (final (status, reason) in transientStatuses) {
      test('HTTP $status keeps the batch queued after the retries', () {
        final api = InProcessPostHogApi()
          ..respond = (_) => PostHogResponse(status);
        final storage = tempStorage();
        fakeAsync((async) {
          final client = testClient(api, storage: storage);
          Object? error;

          client.capture('evt');
          client.flush().catchError((Object e) {
            error = e;
          });
          async.elapse(const Duration(seconds: 9));

          expect(error, isA<PostHogFetchHttpError>());
          expect(api.batchRequests, hasLength(4));
          expect(getQueue(storage), hasLength(1), reason: reason);
        });
      });
    }

    test('a failed flush re-arms the periodic timer', () {
      final api = InProcessPostHogApi();
      var online = false;
      api.respond = (_) => online
          ? const PostHogResponse(HttpStatus.ok)
          : const PostHogResponse.dropped();
      final storage = tempStorage();
      fakeAsync((async) {
        testClient(api, storage: storage).capture('evt');

        // The periodic flush and its retries fail.
        async.elapse(const Duration(seconds: 39));
        expect(api.batchRequests, hasLength(4));

        online = true;
        // Only a re-armed timer can produce the next, successful attempt.
        async.elapse(const Duration(seconds: 30));

        expect(api.batchRequests, hasLength(5));
        expect(getQueue(storage), isEmpty);
      });
    });

    test('the timer firing while a flush is in flight stays re-armable', () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      fakeAsync((async) {
        final release = Completer<void>();
        var online = false;
        api.respond = (_) async {
          await release.future;
          return PostHogResponse(
              online ? HttpStatus.ok : HttpStatus.serviceUnavailable);
        };
        final client = testClient(api,
            config: testConfig(flushInterval: const Duration(milliseconds: 20)),
            storage: storage);

        client.capture('first');
        client.flush().catchError((Object _) {});
        // Arms the timer again while the flush above is still in flight, and
        // lets it fire during that flush.
        client.capture('second');
        async.elapse(const Duration(milliseconds: 60));
        release.complete();
        // The flush and its retries fail.
        async.elapse(const Duration(seconds: 9));
        expect(api.batchRequests, hasLength(4));

        online = true;
        async.elapse(const Duration(milliseconds: 20));

        expect(api.batchRequests.last.eventNames, ['first', 'second'],
            reason: 'only a re-armed timer sends the queue again');
        expect(getQueue(storage), isEmpty);
      });
    });
  });

  group('Retry-After', () {
    for (final status in [429, 503]) {
      test('HTTP $status pauses every send path and resumes the queue', () {
        final api = InProcessPostHogApi();
        final storage = tempStorage();
        fakeAsync((async) {
          api.respond =
              (_) => PostHogResponse(status, headers: {'Retry-After': '120'});
          final client =
              testClient(api, config: testConfig(flushAt: 2), storage: storage);
          Object? error;
          client.capture('first');
          client.flush().catchError((Object e) {
            error = e;
          });
          async.elapse(Duration.zero);

          expect(error, isA<PostHogFetchHttpError>(),
              reason: 'flush should not wait for the server pause to expire');
          final original = api.events.single;
          api.respond = (_) => const PostHogResponse(HttpStatus.ok);
          client.capture('second');
          client.flush();
          client.flush();
          async.elapse(const Duration(seconds: 119));
          expect(api.batchRequests, hasLength(1));
          expect(queuedEvents(storage), ['first', 'second']);

          async.elapse(const Duration(seconds: 1));
          expect(api.batchRequests, hasLength(2));
          expect(api.batchRequests.last.eventNames, ['first', 'second']);
          expect(api.batchRequests.last.events.first['uuid'], original['uuid']);
          expect(api.batchRequests.last.events.first['timestamp'],
              original['timestamp']);
          expect(getQueue(storage), isEmpty);

          client.capture('third');
          client.capture('fourth');
          async.elapse(Duration.zero);
          expect(api.batchRequests, hasLength(3),
              reason: 'the previous pause does not apply after a success');
        });
      });
    }

    for (final header in [
      'invalid',
      '-1',
      '0',
      '',
      'Sun, 06 Nov 1994 08:49:37 GMT',
    ]) {
      test('ignores Retry-After "$header" and keeps three retries', () {
        final api = InProcessPostHogApi()
          ..respond = (_) => PostHogResponse(HttpStatus.serviceUnavailable,
              headers: {'retry-after': header});
        fakeAsync((async) {
          final client = testClient(api);
          Object? error;
          client.capture('event');
          client.flush().catchError((Object e) {
            error = e;
          });
          async.elapse(const Duration(seconds: 9));
          expect(error, isA<PostHogFetchHttpError>());
          expect(api.batchRequests, hasLength(4));
        });
      });
    }

    test('accepts an HTTP date and does not send before it', () {
      final api = InProcessPostHogApi()
        ..respond =
            (_) => PostHogResponse(HttpStatus.serviceUnavailable, headers: {
                  'retry-after': HttpDate.format(
                      DateTime.now().toUtc().add(const Duration(seconds: 120)))
                });
      fakeAsync((async) {
        final client = testClient(api);
        Object? error;
        client.capture('event');
        client.flush().catchError((Object e) {
          error = e;
        });
        async.elapse(Duration.zero);
        expect(error, isA<PostHogFetchHttpError>());
        api.respond = (_) => const PostHogResponse(HttpStatus.ok);
        async.elapse(const Duration(seconds: 118));
        expect(api.batchRequests, hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(api.batchRequests, hasLength(2));
      });
    });

    test('does not retry a permanent error because of the header', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.badRequest,
            headers: {'retry-after': '120'});
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api, storage: storage);
        client.capture('invalid');
        client.flush().catchError((Object _) {});
        async.elapse(Duration.zero);
        expect(getQueue(storage), isEmpty);
        api.respond = (_) => const PostHogResponse(HttpStatus.ok);
        client.capture('valid');
        client.flush();
        async.elapse(Duration.zero);
        expect(api.eventNames, ['invalid', 'valid']);
      });
    });

    test('keeps the pause when consent changes and identity resets', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.tooManyRequests,
            headers: {'retry-after': '120'});
      fakeAsync((async) {
        final client = testClient(api);
        final previousId = client.getDistinctId();
        client.capture('before');
        client.flush().catchError((Object _) {});
        async.elapse(Duration.zero);
        api.respond = (_) => const PostHogResponse(HttpStatus.ok);
        client.optOut();
        client.optIn();
        client.reset();
        final nextId = client.getDistinctId();
        expect(nextId, isNot(previousId));
        client.capture('after');
        client.flush();
        async.elapse(const Duration(seconds: 119));
        expect(api.batchRequests, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        final events = api.batchRequests.last.events;
        expect(events.map((event) => event['event']), ['before', 'after']);
        expect(events[0]['distinct_id'], previousId);
        expect(events[1]['distinct_id'], nextId);
      });
    });

    test('does not send automatically when the interval is zero', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.tooManyRequests,
            headers: {'retry-after': '120'});
      fakeAsync((async) {
        final client = testClient(api,
            config: testConfig(flushAt: 1, flushInterval: Duration.zero));
        client.capture('first');
        async.elapse(Duration.zero);
        api.respond = (_) => const PostHogResponse(HttpStatus.ok);
        client.capture('second');
        client.flush();
        async.elapse(const Duration(seconds: 120));
        expect(api.batchRequests, hasLength(1));
        client.flush();
        client.flush();
        async.elapse(Duration.zero);
        expect(api.batchRequests, hasLength(2));
        expect(api.batchRequests.last.eventNames, ['first', 'second']);
      });
    });

    test('a batch pause does not change flags request retries', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.serviceUnavailable,
            headers: {'retry-after': '120'});
      fakeAsync((async) {
        final client = testClient(api);
        client.capture('event');
        client.flush().catchError((Object _) {});
        async.elapse(Duration.zero);
        api.respond = (_) => const PostHogResponse(HttpStatus.badGateway,
            headers: {'retry-after': '120'});
        client.reloadFeatureFlagsAsync();
        async.elapse(const Duration(milliseconds: 300));
        expect(api.flagsRequests, hasLength(2));
        expect(api.batchRequests, hasLength(1));
        api.respond = (_) => const PostHogResponse(HttpStatus.ok);
        async.elapse(const Duration(milliseconds: 119700));
        expect(api.batchRequests, hasLength(2));
      });
    });

    test('Retry-After in flags does not pause the event queue', () {
      final api = InProcessPostHogApi()
        ..respond = (request) => request.isFlags
            ? const PostHogResponse(HttpStatus.tooManyRequests,
                headers: {'retry-after': '120'})
            : const PostHogResponse(HttpStatus.ok);
      fakeAsync((async) {
        final client = testClient(api);
        client.reloadFeatureFlagsAsync();
        async.elapse(Duration.zero);
        client.capture('event');
        client.flush();
        async.elapse(Duration.zero);
        expect(api.flagsRequests, hasLength(1));
        expect(api.batchRequests.single.eventNames, ['event']);
      });
    });

    test('a new rate limit starts a new pause with the minimum delay', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.tooManyRequests,
            headers: {'retry-after': '60'});
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api, storage: storage);
        client.capture('event');
        client.flush().catchError((Object _) {});
        async.elapse(Duration.zero);
        api.respond = (_) => const PostHogResponse(HttpStatus.tooManyRequests,
            headers: {'retry-after': '1'});
        async.elapse(const Duration(seconds: 60));
        expect(api.batchRequests, hasLength(2));
        api.respond = (_) => const PostHogResponse(HttpStatus.ok);
        client.flush();
        async.elapse(const Duration(milliseconds: 2999));
        expect(api.batchRequests, hasLength(2));
        async.elapse(const Duration(milliseconds: 1));
        expect(api.batchRequests, hasLength(3));
        expect(getQueue(storage), isEmpty);
      });
    });

    test('close cancels the timer and preserves the queue for the next launch',
        () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.tooManyRequests,
            headers: {'retry-after': '120'});
      final dir = tempDirectory();
      fakeAsync((async) {
        final client = testClient(api, storage: FileStorage(dir.path));
        client.capture('event');
        client.flush().catchError((Object _) {});
        async.elapse(Duration.zero);
        client.close();
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 120));
        expect(api.batchRequests, hasLength(1));

        api.respond = (_) => const PostHogResponse(HttpStatus.ok);
        testClient(api, storage: FileStorage(dir.path)).flush();
        async.elapse(Duration.zero);
        expect(api.batchRequests.last.eventNames, ['event']);
      });
    });

    test('a response after close does not create a new timer', () {
      final api = InProcessPostHogApi();
      fakeAsync((async) {
        final response = Completer<PostHogResponse>();
        api.respond = (_) => response.future;
        final client = testClient(api);
        client.capture('event');
        client.flush().catchError((Object _) {});
        async.elapse(Duration.zero);
        client.close();
        response.complete(const PostHogResponse(HttpStatus.tooManyRequests,
            headers: {'retry-after': '120'}));
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
        expect(api.batchRequests, hasLength(1));
      });
    });
  });

  group('Automatic flushing', () {
    test('flushes as soon as the queue reaches flushAt', () async {
      final server = await LocalPostHogServer.start();
      final storage = tempStorage();
      final client =
          testClient(server, config: testConfig(flushAt: 3), storage: storage);

      client.capture('one');
      client.capture('two');
      client.capture('three');
      await server.waitForEvent('three');
      await client.flush();

      expect(server.batchRequests.first.eventNames, ['one', 'two', 'three'],
          reason: 'a flush that took off before flushAt would have sent the '
              'first events on their own');
      expect(getQueue(storage), isEmpty);
    });

    test('drops the oldest events once the queue exceeds maxQueueSize', () {
      final api = InProcessPostHogApi()
        ..respond = (_) => const PostHogResponse(HttpStatus.serviceUnavailable);
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api,
            config: testConfig(
                flushAt: 1, maxQueueSize: 100, flushInterval: Duration.zero),
            storage: storage);
        // Delivery keeps failing, so every event stays queued and only the
        // overflow rule decides which ones survive.

        for (var i = 0; i < 102; i++) {
          client.capture('event_$i');
        }
        async.elapse(const Duration(seconds: 9));

        expect(
            queuedEvents(storage), [for (var i = 2; i <= 101; i++) 'event_$i']);
      });
    });

    test('keeps at most maxQueueSize events, also below flushAt', () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api,
            config: testConfig(flushAt: 20, maxQueueSize: 2, debug: true),
            storage: storage);

        final lines = printedLines(() {
          for (var i = 0; i < 3; i++) {
            client.capture('event_$i');
          }
        });

        expect(queuedEvents(storage), ['event_1', 'event_2']);
        expect(lines, contains(contains('Queue is full')));

        // The queue cannot reach flushAt: the periodic flush sends it.
        async.elapse(const Duration(seconds: 30));
        expect(api.batchRequests.single.eventNames, ['event_1', 'event_2']);
        expect(getQueue(storage), isEmpty);
      });
    });

    test('sends batches of at most maxBatchSize, also below flushAt', () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api,
            config: testConfig(flushAt: 5, maxBatchSize: 2), storage: storage);

        for (var i = 0; i < 5; i++) {
          client.capture('event_$i');
        }
        async.elapse(Duration.zero);

        expect([
          for (final request in api.batchRequests) request.eventNames
        ], [
          ['event_0', 'event_1'],
          ['event_2', 'event_3'],
          ['event_4'],
        ]);
        expect(getQueue(storage), isEmpty);
      });
    });
  });

  group('Queue persistence', () {
    late LocalPostHogServer server;

    setUp(() async {
      server = await LocalPostHogServer.start();
    });

    test('flushes events captured by a previous process from FileStorage',
        () async {
      final dir = tempDirectory();
      testClient(server, storage: FileStorage(dir.path))
        ..capture('sign_in')
        ..capture('sign_out')
        ..close();

      final storage = FileStorage(dir.path);
      await testClient(server, storage: storage).flush();

      expect(server.batchRequests.single.eventNames, ['sign_in', 'sign_out']);
      expect(getQueue(storage), isEmpty);
      expect(Directory('${dir.path}/posthog_queue').listSync(), isEmpty,
          reason: 'delivered events must also leave the on-disk queue');
    });

    test('sends events of a previous run without waiting for a capture',
        () async {
      final dir = tempDirectory();
      testClient(server, storage: FileStorage(dir.path))
        ..capture('sign_in')
        ..close();

      final storage = FileStorage(dir.path);
      final client = testClient(server,
          config: testConfig(flushInterval: const Duration(milliseconds: 20)),
          storage: storage);
      await server.waitForEvent('sign_in');
      await client.flush();

      expect(server.batchRequests.single.eventNames, ['sign_in']);
      expect(getQueue(storage), isEmpty);
    });

    test('retries a queued event after its file becomes readable again',
        () async {
      final dir = tempDirectory();
      testClient(server,
          config: testConfig(flushInterval: Duration.zero),
          storage: FileStorage(dir.path))
        ..capture('persisted')
        ..close();
      final queueFile = Directory('${dir.path}/posthog_queue')
          .listSync()
          .whereType<File>()
          .single;
      chmod('000', queueFile.path);
      addTearDown(() => chmod('644', queueFile.path));

      testClient(server,
          config: testConfig(flushInterval: const Duration(milliseconds: 20)),
          storage: FileStorage(dir.path));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(server.batchRequests, isEmpty);

      chmod('644', queueFile.path);
      await expectLater(
        server.waitForEvent('persisted').timeout(
              const Duration(seconds: 1),
            ),
        completes,
      );
    }, skip: chmodSkip);
  });

  group('PostHogCore.close', () {
    late LocalPostHogServer server;

    setUp(() async {
      server = await LocalPostHogServer.start();
    });

    test('aborts a batch in flight without retrying it; the batch stays queued',
        () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      final received = Completer<void>();
      server.respond = (_) {
        received.complete();
        return Completer<PostHogResponse>().future;
      };
      client.capture('evt');
      final inFlight = client.flush();
      await received.future;

      client.close();

      // Well within the request timeout, so only an aborted request fails.
      await expectLater(inFlight.timeout(const Duration(seconds: 5)),
          throwsA(isA<PostHogFetchNetworkError>()));
      expect(server.batchRequests, hasLength(1), reason: 'it is not retried');
      expect(getQueue(storage), hasLength(1),
          reason: 'the next client using the storage sends it');
    });

    test('closes its connections to PostHog', () async {
      final client = testClient(server);
      client.capture('evt');
      await client.flush();
      expect(server.openConnections, 1,
          reason: 'the client keeps its connection alive between requests');

      client.close();

      await server.connectionsClosed();
    });

    test('ignores calls made afterwards', () async {
      final storage = tempStorage();
      final client =
          testClient(server, config: testConfig(debug: true), storage: storage);
      final distinctId = client.getDistinctId();
      client.close();

      late Future<void> reload;
      final lines = printedLines(() {
        client.capture('After Close');
        client.identify('user-1');
        client.register({'plan': 'pro'});
        reload = client.reloadFeatureFlagsAsync();
      });
      await reload;
      await client.flush();

      expect(getQueue(storage), isEmpty);
      expect(client.getDistinctId(), distinctId);
      expect(
          storage.getProperty<Object>(PostHogPersistedProperty.props), isNull);
      expect(server.requests, isEmpty);
      expect(lines, contains(contains('closed')));
    });

    test('stops the periodic flush', () {
      final api = InProcessPostHogApi();
      fakeAsync((async) {
        final client = testClient(api);
        client.capture('before close');

        client.close();

        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a flush that fails after close does not re-arm the timer', () {
      final api = InProcessPostHogApi();
      fakeAsync((async) {
        final release = Completer<void>();
        api.respond = (_) async {
          await release.future;
          return const PostHogResponse(HttpStatus.serviceUnavailable);
        };
        final client = testClient(api);
        Object? error;
        client.capture('evt');
        client.flush().catchError((Object e) {
          error = e;
        });
        async.elapse(Duration.zero);

        client.close();
        release.complete();
        async.flushMicrotasks();

        expect(error, isA<PostHogFetchHttpError>());
        expect(api.batchRequests, hasLength(1));
        expect(async.pendingTimers, isEmpty,
            reason: 'a re-armed timer would flush a client whose resources '
                'are already released');
      });
    });

    test('releases the storage directory for the next client', () async {
      final dir = tempDirectory();
      testClient(server, storage: FileStorage(dir.path))
        ..capture('queued before close')
        ..close();

      final next = testClient(server, storage: FileStorage(dir.path));
      next.identify('next-user');
      await next.flush();

      expect(
          FileStorage(dir.path)
              .getProperty<String>(PostHogPersistedProperty.distinctId),
          'next-user');
      expect(server.batchRequests.single.eventNames,
          ['queued before close', r'$identify']);
    });
  });
}
