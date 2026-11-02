import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/posthog_core_stateless.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

/// Captures an AI event the way the desktop platform does, without
/// beforeSend callbacks.
String? captureAi(
  DesktopPostHog client,
  String event, {
  Map<String, Object?>? properties,
}) {
  final prepared = client.prepareEvent(event, properties: properties);
  return prepared == null
      ? null
      : client.capturePrepared(event, prepared, ai: true);
}

/// The queued AI events, oldest first.
List<Map<String, Object?>> aiQueue(FileStorage storage) => [
      for (final queued in storage.aiQueue.peek(storage.aiQueue.length))
        queued.event,
    ];

/// A string property that makes an event about [bytes] bytes long.
String filler(int bytes) => 'x' * bytes;

void main() {
  group('captureAi', () {
    late LocalPostHogServer server;

    setUp(() async {
      server = await LocalPostHogServer.start();
    });

    test('sends to the AI endpoint only, and returns the event uuid', () async {
      final client = testClient(server);

      final uuid = captureAi(client, r'$ai_generation',
          properties: {r'$ai_model': 'gpt-5'});
      client.capture(r'$ai_generation');
      await client.flush();

      final request = server.aiRequests.single;
      final event = request.events.single;
      expect(event['uuid'], uuid);
      expect(event['event'], r'$ai_generation');
      expect((event['properties']! as Map)[r'$ai_model'], 'gpt-5');
      expect(event['session_id'], isA<String>());
      expect(request.body['created_at'], isA<String>());
      expect(request.headers['authorization'], 'Bearer k');
      expect(
          request.headers['posthog-sdk-info'], startsWith('posthog-flutter/'));
      expect(request.headers['posthog-attempt'], '1');
      expect(request.headers['content-encoding'], 'gzip');
      expect(server.batchRequests.single.eventNames, [r'$ai_generation'],
          reason: 'capture never sends to the AI endpoint');
    });

    test('compresses with captureAiCompression, apart from compression',
        () async {
      final client = testClient(server,
          config: testConfig()..captureAiCompression = PostHogCompression.none);

      captureAi(client, r'$ai_generation');
      client.capture('event');
      await client.flush();

      expect(server.aiRequests.single.headers,
          isNot(contains('content-encoding')));
      expect(server.batchRequests.single.headers['content-encoding'], 'gzip');
    });

    test('returns null and queues nothing while opted out', () {
      final storage = tempStorage();
      final client = testClient(server,
          config: testConfig(optOut: true), storage: storage);

      expect(captureAi(client, r'$ai_generation'), isNull);
      expect(aiQueue(storage), isEmpty);
    });

    test('drops a serialized event over the limit, logging name and size only',
        () {
      final storage = tempStorage();
      final client = testClient(server,
          config: testConfig(debug: true)..captureAiMaxEventBytes = 10000,
          storage: storage);

      late String? fits;
      final lines = printedLines(() {
        fits =
            captureAi(client, r'$ai_span', properties: {'input': filler(1000)});
      });
      expect(fits, isNotNull);
      final size = utf8.encode(jsonEncode(aiQueue(storage).single)).length;

      final secret = 'secret-${filler(10000)}';
      String? oversized = 'not called';
      final dropLines = printedLines(() {
        oversized =
            captureAi(client, r'$ai_generation', properties: {'input': secret});
      });

      expect(oversized, isNull);
      expect(aiQueue(storage), hasLength(1));
      expect(size, lessThan(10000));
      expect(lines, isNot(contains(contains('Dropping'))));
      final drop = dropLines.singleWhere((line) => line.contains('Dropping'));
      expect(drop, contains(r'$ai_generation'));
      expect(drop, contains('over the 10000 byte limit'));
      expect(dropLines.join(), isNot(contains('secret')));
    });

    test('caps captureAiMaxEventBytes at 8 MiB plus 64 KiB, with a warning',
        () {
      final storage = tempStorage();
      late DesktopPostHog client;
      final lines = printedLines(() {
        client = testClient(server,
            config: testConfig(debug: true)
              ..captureAiMaxEventBytes = 100 * 1024 * 1024,
            storage: storage);
      });

      expect(
          lines.where((line) => line.contains('byte ceiling')), hasLength(1));

      expect(
        captureAi(client, r'$ai_generation',
            properties: {'input': filler(8 * 1024 * 1024 + 64 * 1024)}),
        isNull,
      );
      expect(
        captureAi(client, r'$ai_generation',
            properties: {'input': filler(8 * 1024 * 1024)}),
        isNotNull,
      );
    });

    test('keeps captureAiMaxQueueSize AI events, apart from maxQueueSize', () {
      final storage = tempStorage();
      final client = testClient(server,
          config: testConfig(maxQueueSize: 1)..captureAiMaxQueueSize = 3,
          storage: storage);

      for (var i = 0; i < 5; i++) {
        captureAi(client, r'$ai_span', properties: {'i': i});
      }
      client.capture('a');
      client.capture('b');

      expect([
        for (final event in aiQueue(storage)) (event['properties']! as Map)['i']
      ], [
        2,
        3,
        4
      ]);
      expect(queuedEvents(storage), ['b']);
    });

    test('keeps at most 50 MiB of AI events, always the newest', () {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);

      for (var i = 0; i < 7; i++) {
        captureAi(client, r'$ai_span',
            properties: {'i': i, 'input': filler(8 * 1024 * 1024)});
      }

      expect([
        for (final event in aiQueue(storage)) (event['properties']! as Map)['i']
      ], [
        1,
        2,
        3,
        4,
        5,
        6
      ]);
      expect(storage.aiQueue.byteCount, lessThanOrEqualTo(50 * 1024 * 1024));
    });

    test('flushes once 5 MiB of AI events are queued, below flushAt', () async {
      final client = testClient(server);

      captureAi(client, r'$ai_span', properties: {'input': filler(3 << 20)});
      expect(server.aiRequests, isEmpty);
      captureAi(client, r'$ai_span', properties: {'input': filler(3 << 20)});

      await server.waitForAiEvent(r'$ai_span');
    });

    test('AI events of a previous run are sent by the next client', () async {
      final dir = tempDirectory();
      final first = testClient(server, storage: FileStorage(dir.path));
      final uuid = captureAi(first, r'$ai_trace');
      first.close();
      final next = testClient(server, storage: FileStorage(dir.path));

      await next.flush();

      expect(server.aiEvents.single['uuid'], uuid);
      expect(Directory('${dir.path}/posthog_ai_queue').listSync(), isEmpty);
    });

    test('a 400 drops the AI batch without a retry', () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (request) => request.isAi
          ? const PostHogResponse(HttpStatus.badRequest)
          : const PostHogResponse(HttpStatus.ok);

      captureAi(client, r'$ai_generation');
      client.capture('event');
      await expectLater(client.flush(), throwsA(isA<PostHogFetchHttpError>()));

      expect(server.aiRequests, hasLength(1));
      expect(aiQueue(storage), isEmpty);
      expect(server.eventNames, ['event'],
          reason: 'an AI failure does not hold back the other events');
    });

    test('a per-event retry keeps only that AI event queued', () async {
      final storage = tempStorage();
      final client = testClient(server, storage: storage);
      server.respond = (request) => request.isAi
          ? PostHogResponse.results(
              request, (name) => name == r'$ai_span' ? 'retry' : null)
          : const PostHogResponse(HttpStatus.ok);

      captureAi(client, r'$ai_generation');
      captureAi(client, r'$ai_span');
      await client.flush();

      expect([for (final event in aiQueue(storage)) event['event']],
          [r'$ai_span']);
    });

    test(
        'a transient failure keeps the AI batch queued, retried under its own '
        'request identity', () {
      final api = InProcessPostHogApi()
        ..respond = (request) => request.isAi
            ? const PostHogResponse(HttpStatus.serviceUnavailable)
            : const PostHogResponse(HttpStatus.ok);
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api, storage: storage);

        captureAi(client, r'$ai_generation');
        client.flush().catchError((Object _) {});
        async.elapse(const Duration(seconds: 1));
        client.capture('event');
        client.flush().catchError((Object _) {});
        async.elapse(const Duration(seconds: 9));

        expect(aiQueue(storage), hasLength(1));
        final attempts = [
          for (final request in api.aiRequests)
            request.headers['posthog-attempt'],
        ];
        expect(attempts, ['1', '2', '3', '4']);
        expect(
            {for (final r in api.aiRequests) r.headers['posthog-request-id']},
            hasLength(1));
        expect(api.batchRequests.single.headers['posthog-attempt'], '1');
      });
    });

    test('the AI and analytics endpoints back off independently', () {
      var batchStatus = HttpStatus.serviceUnavailable;
      final api = InProcessPostHogApi()
        ..respond = (request) => PostHogResponse(
            request.isAi ? HttpStatus.serviceUnavailable : batchStatus);
      final storage = tempStorage();
      fakeAsync((async) {
        final client = testClient(api, storage: storage);

        // AI fails at 0, 1 and 3 s: its next retry is 4 s later, at 7 s.
        captureAi(client, r'$ai_generation');
        client.flush().catchError((Object _) {});
        async.elapse(const Duration(milliseconds: 3500));
        expect(api.aiRequests, hasLength(3));

        // Analytics starts its own backoff at 1 s, not at AI's 8 s.
        client.capture('event');
        client.flush().catchError((Object _) {});
        async.flushMicrotasks();
        expect(api.batchRequests, hasLength(1));
        batchStatus = HttpStatus.ok;
        async.elapse(const Duration(milliseconds: 900));
        expect(api.batchRequests, hasLength(1));
        async.elapse(const Duration(milliseconds: 200));
        expect(api.batchRequests, hasLength(2));
        expect(storage.queue.length, 0);

        // The delivered analytics batch leaves AI's backoff where it was.
        async.elapse(const Duration(milliseconds: 2300)); // 6.9 s
        expect(api.aiRequests, hasLength(3));
        async.elapse(const Duration(milliseconds: 200)); // 7.1 s
        expect(api.aiRequests, hasLength(4));
        expect(aiQueue(storage), hasLength(1));
      });
    });
  });
}
