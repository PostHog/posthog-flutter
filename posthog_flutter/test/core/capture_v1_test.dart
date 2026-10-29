import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/capture_v1.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/logger.dart';
import 'package:posthog_flutter/src/core/posthog_core_stateless.dart';
import 'package:posthog_flutter/src/core/uuid.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

final _uuidPattern =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

void main() {
  group('Capture v1 request', () {
    test('posts the v1 envelope with bearer auth and request headers',
        () async {
      final server = await LocalPostHogServer.start();
      final client = testClient(server);

      client.capture('first', properties: {'plan': 'pro'});
      client.capture('second');
      await client.flush();

      final request = server.batchRequests.single;
      expect(request.path, '/i/v1/analytics/events');
      expect(request.headers['authorization'], 'Bearer k');
      expect(request.headers['posthog-sdk-info'],
          '$postHogFlutterSdkName/$postHogFlutterVersion');
      expect(request.headers['posthog-attempt'], '1');
      expect(request.headers['posthog-request-id'], matches(_uuidPattern));
      expect(
          DateTime.parse(request.headers['posthog-request-timestamp']!).isUtc,
          isTrue);
      expect(request.body.keys, unorderedEquals(['created_at', 'batch']));
      expect(
          DateTime.parse(request.body['created_at']! as String).isUtc, isTrue);

      for (final event in request.events) {
        expect(
            event.keys,
            unorderedEquals([
              'event',
              'uuid',
              'distinct_id',
              'timestamp',
              'session_id',
              'options',
              'properties',
            ]));
        expect(event['uuid'], matches(_uuidPattern));
        expect(event['distinct_id'], client.getDistinctId());
        expect(event['session_id'], client.getSessionId());
        expect(event['options'], {'process_person_profile': false});
        final properties = event['properties']! as Map;
        for (final moved in [
          r'$lib',
          r'$lib_version',
          r'$session_id',
          r'$process_person_profile',
        ]) {
          expect(properties, isNot(contains(moved)));
        }
      }
      expect(request.events.first['properties'], containsPair('plan', 'pro'));
    });

    test('moves the legacy option properties into options', () async {
      final server = await LocalPostHogServer.start();
      final client = testClient(server);

      client.capture('tour', properties: {
        r'$cookieless_mode': true,
        r'$ignore_sent_at': true,
        r'$product_tour_id': 'tour-1',
      });
      await client.flush();

      final event = server.events.single;
      expect(event['options'], {
        'cookieless_mode': true,
        'disable_skew_correction': true,
        'product_tour_id': 'tour-1',
        'process_person_profile': false,
      });
      expect(
          (event['properties']! as Map).keys,
          isNot(anyOf(contains(r'$cookieless_mode'),
              contains(r'$ignore_sent_at'), contains(r'$product_tour_id'))));
    });
  });

  group('captureV1Event', () {
    final logger = CoreLogger((_) {});

    test('keeps a set option over the legacy property, and fills a null one',
        () {
      final event = captureV1Event({
        'event': 'e',
        'uuid': 'u',
        'distinct_id': 'd',
        'timestamp': 't',
        'options': {'process_person_profile': true, 'cookieless_mode': null},
        'properties': {
          r'$process_person_profile': false,
          r'$cookieless_mode': true,
          'kept': 1,
        },
      }, logger);

      expect(event['options'], {
        'process_person_profile': true,
        'cookieless_mode': true,
      });
      expect(event['properties'], {'kept': 1});
    });

    test('omits options when none is set', () {
      final event = captureV1Event({
        'event': 'e',
        'properties': {'kept': 1},
      }, logger);

      expect(event, isNot(contains('options')));
    });

    test('lifts string session and window ids, empty ones included', () {
      final event = captureV1Event({
        'event': 'e',
        'properties': {r'$session_id': '', r'$window_id': 'w'},
      }, logger);

      expect(event['session_id'], '');
      expect(event['window_id'], 'w');
      expect(event['properties'], isEmpty);
    });

    test('drops a non-string session id with a warning naming its type', () {
      final lines = <String>[];
      final event = captureV1Event({
        'event': 'e',
        'properties': {r'$session_id': 42, r'$window_id': null},
      }, CoreLogger((log) => lines.addAll(printedLines(log))));

      expect(event, isNot(contains('session_id')));
      expect(event, isNot(contains('window_id')));
      expect(event['properties'], isEmpty);
      expect(lines.single, contains(r'$session_id'));
      expect(lines.single, contains('number'));
      expect(lines.single, isNot(contains('42')));
    });

    test('names the JSON type of a boolean session id', () {
      final lines = <String>[];
      captureV1Event({
        'event': 'e',
        'properties': {r'$window_id': true},
      }, CoreLogger((log) => lines.addAll(printedLines(log))));

      expect(lines.single, contains('a boolean value'));
    });
  });

  group('captureRetryDelay', () {
    Duration delay(int attempt, double unit, [int? retryAfterSeconds]) =>
        captureRetryDelay(
          attempt: attempt,
          jitterUnit: unit,
          retryAfter: retryAfterSeconds == null
              ? null
              : Duration(seconds: retryAfterSeconds),
        );

    test('doubles from 1 second up to 30 seconds', () {
      expect([for (var a = 1; a <= 7; a++) delay(a, 0.5).inSeconds],
          [1, 2, 4, 8, 16, 30, 30]);
    });

    test('jitters by up to 25 percent and stays under 30 seconds', () {
      expect(delay(1, 0), const Duration(milliseconds: 750));
      expect(delay(3, 0.75), const Duration(milliseconds: 4500));
      expect(delay(6, 0), const Duration(milliseconds: 22500));
      expect(delay(6, 0.999), const Duration(seconds: 30));
      expect(delay(1, double.nan), const Duration(seconds: 1));
      expect(delay(1, 1), const Duration(seconds: 1));
    });

    test('takes Retry-After as a floor after the jitter, at most 30 s', () {
      expect(delay(1, 0, 5), const Duration(seconds: 5));
      expect(delay(4, 0.5, 1), const Duration(seconds: 8));
      expect(delay(4, 0, 7), const Duration(seconds: 7));
      expect(delay(1, 0.5, 120), const Duration(seconds: 30));
    });
  });

  group('Capture v1 results', () {
    test('resends only the events the server asks to retry', () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      final results = {
        'ok': 'ok',
        'warned': 'warning',
        'dropped': 'drop',
        'limited': 'limited',
        'unknown': 'unknown_future_result',
        'retried': 'retry',
      };
      fakeAsync((async) {
        final client =
            testClient(api, config: testConfig(debug: true), storage: storage);
        results.keys.forEach(client.capture);
        // Left out of the results: counts as delivered.
        client.capture('missing');
        api.respond = (request) => api.batchRequests.length == 1
            ? PostHogResponse.json({
                'results': {
                  for (final event in request.events)
                    if (event['event'] != 'missing')
                      '${event['uuid']}': {
                        'result': results[event['event']],
                        'details': 'detail',
                      },
                },
              })
            : PostHogResponse.results(request, (_) => 'ok');

        final lines = printedLines(() {
          client.flush();
          async.elapse(Duration.zero);
        });
        expect(api.batchRequests, hasLength(1));
        expect(queuedEvents(storage), ['retried']);
        final uuids = [
          for (final event in api.batchRequests.single.events) event['uuid'],
        ];
        // `limited` and unknown results count as delivered, like `ok`.
        final rejection = lines.singleWhere((line) => line
            .contains('/i/v1/analytics/events dropped 1 of 7 events for good '
                '(detail: 1)'));
        for (final uuid in uuids) {
          expect(rejection, isNot(contains('$uuid')));
        }

        async.elapse(const Duration(seconds: 3));
        expect(api.batchRequests, hasLength(2));
        final first = api.batchRequests[0];
        final retry = api.batchRequests[1];
        expect(retry.eventNames, ['retried']);
        expect(retry.events.single['uuid'],
            first.events.firstWhere((e) => e['event'] == 'retried')['uuid']);
        expect(retry.headers['posthog-request-id'],
            first.headers['posthog-request-id']);
        expect(retry.headers['posthog-attempt'], '2');
        expect(retry.body['created_at'], first.body['created_at']);
        expect(getQueue(storage), isEmpty);
        async.elapse(const Duration(seconds: 30));
        expect(api.batchRequests, hasLength(2));
      });
    });

    test('waits for the Retry-After of a partial retry, at most 30 seconds',
        () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      api.respond = (request) => api.batchRequests.length == 1
          ? PostHogResponse.results(
              request, (name) => name == 'later' ? 'retry' : null,
              headers: {'Retry-After': '120'})
          : PostHogResponse.results(request, (_) => 'ok');
      fakeAsync((async) {
        final client = testClient(api, storage: storage);
        client.capture('now');
        client.capture('later');
        client.flush();

        async.elapse(const Duration(seconds: 29));
        expect(api.batchRequests, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(api.batchRequests, hasLength(2));
        expect(api.batchRequests.last.eventNames, ['later']);
        expect(api.batchRequests.last.headers['posthog-attempt'], '2');
        expect(getQueue(storage), isEmpty);
      });
    });

    test('a partial retry advances the backoff, a full delivery resets it', () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      var partial = 3;
      api.respond = (request) => partial-- > 0
          ? PostHogResponse.results(
              request, (name) => name == 'later' ? 'retry' : null)
          : PostHogResponse.results(request, (_) => 'ok');
      fakeAsync((async) {
        final client = testClient(api, storage: storage);
        client.capture('now');
        client.capture('later');
        client.flush();
        async.elapse(Duration.zero);

        var now = Duration.zero;
        var requests = 1;
        for (final next in [1, 3, 7]) {
          async.elapse(Duration(seconds: next) - now - _ms);
          expect(api.batchRequests, hasLength(requests));
          async.elapse(_ms);
          expect(api.batchRequests, hasLength(++requests));
          now = Duration(seconds: next);
        }
        expect(getQueue(storage), isEmpty);

        api.respond = (_) => const PostHogResponse(HttpStatus.badGateway);
        client.capture('next');
        client.flush().catchError((Object _) {});
        async.elapse(const Duration(seconds: 1) - _ms);
        expect(api.batchRequests, hasLength(5));
        async.elapse(_ms);
        expect(api.batchRequests, hasLength(6),
            reason: 'the backoff starts over at 1 second');
      });
    });

    test('starts a new request when new events join a retried batch', () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      api.respond = (request) => api.batchRequests.length == 1
          ? PostHogResponse.results(
              request, (name) => name == 'retried' ? 'retry' : null,
              headers: {'Retry-After': '5'})
          : PostHogResponse.results(request, (_) => 'ok');
      fakeAsync((async) {
        final client = testClient(api, storage: storage);
        client.capture('retried');
        client.flush();
        async.elapse(Duration.zero);
        client.capture('joined');
        async.elapse(const Duration(seconds: 5));

        final [first, second] = api.batchRequests;
        expect(second.eventNames, ['retried', 'joined']);
        expect(second.headers['posthog-request-id'],
            isNot(first.headers['posthog-request-id']));
        expect(second.headers['posthog-attempt'], '1');
        expect(getQueue(storage), isEmpty);
      });
    });

    test('keeps the request identity across retries of a failed request', () {
      final api = InProcessPostHogApi();
      var failures = 2;
      api.respond = (_) => failures-- > 0
          ? const PostHogResponse(HttpStatus.badGateway)
          : const PostHogResponse(HttpStatus.ok);
      fakeAsync((async) {
        final client = testClient(api);
        client.capture('evt');
        client.flush().catchError((Object _) {});
        async.elapse(const Duration(seconds: 6));

        final requests = api.batchRequests;
        expect([for (final r in requests) r.headers['posthog-attempt']],
            ['1', '2', '3']);
        expect({for (final r in requests) r.headers['posthog-request-id']},
            hasLength(1));
        expect({for (final r in requests) r.body['created_at']}, hasLength(1));
      });
    });

    test('counts the duplicate copies capture dropped', () {
      final body = jsonEncode({
        'results': {
          'a': {'result': 'ok', 'duplicates_dropped': 2},
          'b': {'result': 'retry', 'duplicates_dropped': 1},
          'c': {'result': 'ok'},
        },
      });

      final results = captureV1Results(body, ['a', 'b', 'c'])!;

      expect(results.duplicates, 3);
      expect(results.retry, {'b'});
    });

    test('clamps malformed duplicates_dropped to the batch size', () {
      final body = jsonEncode({
        'results': {
          'a': {'result': 'ok', 'duplicates_dropped': 9007199254740991},
          'b': {'result': 'ok', 'duplicates_dropped': -5},
          'c': {'result': 'ok', 'duplicates_dropped': '2'},
        },
      });

      expect(captureV1Results(body, ['a', 'b', 'c'])!.duplicates, 3);
    });

    test('clamps duplicates_dropped against every copy sent', () {
      final body = jsonEncode({
        'results': {
          'a': {'result': 'drop', 'duplicates_dropped': 2},
        },
      });

      final results = captureV1Results(body, ['a', 'a', 'a'])!;

      expect(results.duplicates, 2);
      expect(results.drops, {'no details': 1});
    });

    test('drops a 2xx without readable results without retrying it', () async {
      final server = await LocalPostHogServer.start();
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond =
          (_) => const PostHogResponse(HttpStatus.ok, body: 'not json');
      final errors = <Object?>[];
      // ignore: invalid_use_of_protected_member
      client.events.on('error', errors.add);
      final flushed = <Object?>[];
      // ignore: invalid_use_of_protected_member
      client.events.on('flush', flushed.add);

      client.capture('evt');
      await expectLater(client.flush(), throwsA(isA<PostHogFetchHttpError>()));

      expect(server.batchRequests, hasLength(1));
      expect(getQueue(storage), isEmpty);
      expect(errors, hasLength(1));
      expect(flushed, isEmpty);
    });

    test('logs the endpoint and count of a batch lost to a terminal status',
        () {
      final api = InProcessPostHogApi();
      final storage = tempStorage();
      fakeAsync((async) {
        final client =
            testClient(api, config: testConfig(debug: true), storage: storage);
        api.respond = (request) => request.isFlags
            ? PostHogResponse.json({'flags': <String, Object?>{}})
            : const PostHogResponse(HttpStatus.badRequest);
        client.capture('one');
        client.capture('two');

        final lines = printedLines(() {
          client.flush().catchError((_) {});
          async.elapse(Duration.zero);
        });

        expect(api.batchRequests, hasLength(1));
        expect(queuedEvents(storage), isEmpty);
        expect(
            lines,
            contains(contains('Capture /i/v1/analytics/events returned 400: '
                '2 events dropped for good.')));
      });
    });

    test('drops a single event that is still too large', () async {
      final server = await LocalPostHogServer.start();
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond =
          (_) => const PostHogResponse(HttpStatus.requestEntityTooLarge);

      client.capture('huge');
      await expectLater(client.flush(), throwsA(isA<PostHogFetchHttpError>()));

      expect(server.batchRequests, hasLength(1));
      expect(getQueue(storage), isEmpty);
    });

    test('retries a 404 without falling back to /batch', () {
      final api = InProcessPostHogApi()
        ..respond = (request) => request.isFlags
            ? PostHogResponse.json({'flags': <String, Object?>{}})
            : const PostHogResponse(HttpStatus.notFound);
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
        expect([for (final r in api.requests) r.path],
            List.filled(4, '/i/v1/analytics/events'));
        expect(getQueue(storage), hasLength(1));
      });
    });
  });

  group('Capture v1 redirects', () {
    test('follows a same-origin 307 with the body and headers', () async {
      final server = await LocalPostHogServer.start();
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (request) => request.path == '/i/v1/analytics/events'
          ? PostHogResponse(HttpStatus.temporaryRedirect,
              location: '${server.url}/moved/events')
          : PostHogResponse.results(request, (_) => 'ok');

      client.capture('evt');
      await client.flush();

      final [original, moved] = server.requests;
      expect(moved.path, '/moved/events');
      expect(moved.body, original.body);
      for (final header in [
        'authorization',
        'posthog-request-id',
        'posthog-attempt',
        'content-encoding',
      ]) {
        expect(moved.headers[header], original.headers[header]);
      }
      expect(getQueue(storage), isEmpty);
    });

    test('stops after five redirects and drops the batch', () async {
      final server = await LocalPostHogServer.start();
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (request) => PostHogResponse(
          HttpStatus.permanentRedirect,
          location: '${server.url}/hop${server.requests.length}');

      client.capture('evt');
      await expectLater(
          client.flush(),
          throwsA(isA<PostHogFetchHttpError>()
              .having((e) => e.status, 'status', 308)));

      expect(server.requests, hasLength(6));
      expect(getQueue(storage), isEmpty);
    });
  });

  test('sends events queued by posthog_flutter 5.x through capture v1',
      () async {
    final server = await LocalPostHogServer.start();
    final dir = tempDirectory();
    // An event as posthog_flutter 5.56 queued it for /batch/.
    final legacy = {
      'distinct_id': 'user-1',
      'event': 'legacy event',
      'properties': {
        'plan': 'pro',
        r'$lib': 'posthog-flutter',
        r'$lib_version': '5.56.2',
        r'$session_id': '0199aa00-0000-7000-8000-000000000001',
        r'$process_person_profile': true,
        r'$is_identified': true,
      },
      'type': 'capture',
      'library': 'posthog-flutter',
      'library_version': '5.56.2',
      'timestamp': '2026-10-01T12:00:00.000Z',
      'uuid': '0199aa00-0000-7000-8000-000000000002',
    };
    File('${dir.path}/posthog_queue/${generateUuidV7()}.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(legacy));

    await testClient(server, storage: FileStorage(dir.path)).flush();

    expect(server.events.single, {
      'event': 'legacy event',
      'uuid': '0199aa00-0000-7000-8000-000000000002',
      'distinct_id': 'user-1',
      'timestamp': '2026-10-01T12:00:00.000Z',
      'session_id': '0199aa00-0000-7000-8000-000000000001',
      'options': {'process_person_profile': true},
      'properties': {'plan': 'pro', r'$is_identified': true},
    });
    expect(Directory('${dir.path}/posthog_queue').listSync(), isEmpty);
  });
}

const _ms = Duration(milliseconds: 1);
