import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/queue_worker.dart';

import '../posthog_api_fake.dart';

import 'test_client.dart';

void main() {
  late Directory dir;
  late QueueWorker worker;

  setUp(() {
    dir = tempDirectory();
    worker = QueueWorker.isolate();
  });

  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

  group('QueueWorker.isolate', () {
    test('writes an event on a background isolate and reports its size',
        () async {
      final event = {'event': 'é', 'n': 1};

      final result = await worker.write(pathOf('a.json'), event);

      expect(worker.runsInBackground, isTrue);
      expect(result.bytes, utf8.encode(jsonEncode(event)).length);
      expect(result.tooLarge, isFalse);
      expect(result.error, isNull);
      expect(jsonDecode(File(pathOf('a.json')).readAsStringSync()), event);
    });

    test('measures an event without writing it when it has no path', () async {
      final result = await worker.write(null, {'event': 'x'});

      expect(result.bytes, '{"event":"x"}'.length);
      expect(dir.listSync(), isEmpty);
    });

    test('does not write an event over maxBytes', () async {
      final result =
          await worker.write(pathOf('a.json'), {'p': 'x' * 100}, maxBytes: 50);

      expect(result.tooLarge, isTrue);
      expect(result.bytes, greaterThan(50));
      expect(File(pathOf('a.json')).existsSync(), isFalse);
    });

    test('reports an event that cannot be encoded', () async {
      final result = await worker.write(pathOf('a.json'), {'p': double.nan});

      expect(result.bytes, isNull);
      expect(result.error, isNotNull);
      expect(File(pathOf('a.json')).existsSync(), isFalse);
    });

    test('reports a write that fails', () async {
      final blocker = File(pathOf('blocker'))..writeAsStringSync('');

      final result =
          await worker.write('${blocker.path}/a.json', {'event': 'x'});

      expect(result.error, isNotNull);
      expect(result.bytes, isNotNull);
    });

    test('runs jobs in the order they were submitted', () async {
      // Not awaited one by one: the deletes must still come after the writes.
      final jobs = <Future<Object?>>[];
      for (var i = 0; i < 20; i++) {
        jobs.add(worker.write(pathOf('$i.json'), {'i': i}));
      }
      jobs.add(worker.delete([for (var i = 0; i < 10; i++) pathOf('$i.json')]));
      jobs.add(worker.write(pathOf('0.json'), {'i': 'again'}));
      await Future.wait(jobs);

      final names = [
        for (final file in dir.listSync()) file.uri.pathSegments.last,
      ]..sort();
      expect(
          names,
          [
            '0.json',
            for (var i = 10; i < 20; i++) '$i.json',
          ]..sort());
      expect(jsonDecode(File(pathOf('0.json')).readAsStringSync()),
          {'i': 'again'});
    });

    test('reads events, and deletes the ones that cannot be decoded', () async {
      File(pathOf('good.json')).writeAsStringSync('{"event":"good"}');
      File(pathOf('bad.json')).writeAsStringSync('not json');
      File(pathOf('list.json')).writeAsStringSync('[1]');

      final results = await worker.read([
        pathOf('good.json'),
        pathOf('bad.json'),
        pathOf('list.json'),
        pathOf('missing.json'),
      ]);

      expect(results[0].event, {'event': 'good'});
      expect([for (final r in results.skip(1)) r.gone], [true, true, true]);
      expect(results[1].error, isNotNull);
      expect(results[3].error, isNull);
      expect(File(pathOf('bad.json')).existsSync(), isFalse);
      expect(File(pathOf('list.json')).existsSync(), isFalse);
    });

    test('ignores a file that is already deleted', () async {
      expect(await worker.delete([pathOf('missing.json')]), isEmpty);
    });

    test('encodes and gzips a request body', () async {
      final body = {
        'batch': [
          {'p': 'é' * 1000},
        ],
      };
      final json = utf8.encode(jsonEncode(body));

      final gzipped = await worker.encodeBody(body, gzip: true);
      final plain = await worker.encodeBody(body, gzip: false);

      expect(gzipped.length, json.length);
      expect(gzip.decode(gzipped.payload), json);
      expect(plain.payload, json);
      expect(plain.length, json.length);
    });

    test(
        'runs the jobs it had not answered on the calling isolate when it '
        'stops', () async {
      await worker.write(pathOf('before.json'), {'i': 0});

      worker.kill();
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) worker.write(pathOf('$i.json'), {'i': i}),
      ]);

      expect(worker.runsInBackground, isFalse);
      expect([for (final r in results) r.error], everyElement(isNull));
      for (var i = 0; i < 5; i++) {
        expect(File(pathOf('$i.json')).existsSync(), isTrue);
      }
      // Later jobs run on the calling isolate too.
      await worker.delete([pathOf('0.json')]);
      expect(File(pathOf('0.json')).existsSync(), isFalse);
    });
  });

  group('FileEventQueue with a background worker', () {
    FileStorage storage() {
      final storage = FileStorage(dir.path, worker: worker);
      addTearDown(storage.close);
      return storage;
    }

    List<File> queueFiles() => Directory(pathOf('posthog_queue')).existsSync()
        ? Directory(pathOf('posthog_queue'))
            .listSync()
            .whereType<File>()
            .toList()
        : [];

    test('takes the event in the queue at once and counts it once written',
        () async {
      final queue = storage().queue;

      final added = queue.add({'event': 'a'});

      expect(queue.length, 1);
      expect((await added).bytes, '{"event":"a"}'.length);
      expect(queue.byteCount, '{"event":"a"}'.length);
      expect(queueFiles(), hasLength(1));
    });

    test('a peek waits for the events being written', () async {
      final queue = storage().queue;
      for (var i = 0; i < 10; i++) {
        queue.add({'i': i});
      }

      final events = await queue.peek(100);

      expect([for (final queued in events) queued.event['i']],
          List.generate(10, (i) => i));
      expect(queueFiles(), hasLength(10));
    });

    test('a peek does not wait for events added after it', () async {
      final queue = storage().queue;
      queue.add({'i': 0});
      var peeked = false;
      var next = 1;
      void keepAdding() {
        if (!peeked) queue.add({'i': next++}).then((_) => keepAdding());
      }

      keepAdding();
      final events = await queue.peek(1);
      peeked = true;

      expect(events.single.event['i'], 0);
    });

    test('a peek leaves an event that can still be dropped for its size',
        () async {
      final queue = storage().queue;
      queue.add({'i': 0});

      final peek = queue.peek(100);
      queue.add({'i': 'x' * 100}, maxBytes: 10);

      expect([for (final queued in await peek) queued.event['i']], [0]);
    });

    test('reads events written by an earlier storage', () async {
      final first = storage();
      for (var i = 0; i < 3; i++) {
        first.queue.add({'i': i});
      }
      await first.settled;
      first.close();

      final next = FileStorage(dir.path, worker: worker);
      addTearDown(next.close);
      final events = await next.queue.peek(10);

      expect([for (final queued in events) queued.event['i']], [0, 1, 2]);
    });

    test('an event removed while it is written leaves no file', () async {
      final queue = storage().queue;
      queue.add({'event': 'a'});

      queue.removeOldest(1);
      await queue.settled;

      expect(queue.length, 0);
      expect(queue.byteCount, 0);
      expect(queueFiles(), isEmpty);
    });

    test('drops an event over maxBytes without writing it', () async {
      final queue = storage().queue;

      final result = await queue.add({'p': 'x' * 100}, maxBytes: 50);

      expect(result.tooLarge, isTrue);
      expect(queue.length, 0);
      expect(queueFiles(), isEmpty);
    });

    test('keeps an event it cannot write in memory', () async {
      // A file where the queue directory should be fails every write.
      File(pathOf('posthog_queue')).writeAsStringSync('');
      final queue = storage().queue;

      final result = await queue.add({'event': 'a'});

      expect(result.error, isNotNull);
      expect(queue.byteCount, '{"event":"a"}'.length);
      expect([for (final queued in await queue.peek(10)) queued.event['event']],
          ['a']);
    });

    test('settled waits for the deletions', () async {
      final queue = storage().queue;
      for (var i = 0; i < 5; i++) {
        queue.add({'i': i});
      }
      await queue.settled;

      queue.remove([for (final queued in await queue.peek(5)) queued.id]);
      await queue.settled;

      expect(queueFiles(), isEmpty);
    });
  });

  group('PostHogCore with a background worker', () {
    test('sends and deletes the events it queued', () async {
      final server = await LocalPostHogServer.start();
      final storage = FileStorage(dir.path, worker: worker);
      final client = testClient(server, storage: storage);

      client.capture('a');
      client.capture('b');
      await client.flush();
      await client.settled;

      expect(server.batchRequests.single.eventNames, ['a', 'b']);
      expect(storage.queue.length, 0);
      expect(Directory(pathOf('posthog_queue')).listSync().whereType<File>(),
          isEmpty);
    });

    test('an AI event still being measured does not evict a kept one',
        () async {
      final server = await LocalPostHogServer.start();
      final storage = FileStorage(dir.path, worker: worker);
      final client = testClient(server,
          config: testConfig()
            ..captureAiMaxQueueSize = 1
            ..captureAiMaxEventBytes = 1000,
          storage: storage);

      final kept = client.captureAiPrepared(
          r'$ai_span', client.prepareEvent(r'$ai_span')!);
      final oversized = client.captureAiPrepared(r'$ai_span',
          client.prepareEvent(r'$ai_span', properties: {'input': 'x' * 2000})!);

      final uuid = await kept;
      expect(uuid, isNotNull);
      expect(await oversized, isNull);
      expect(storage.aiQueue.length, 1);
      expect((await storage.aiQueue.peek(1)).single.event['uuid'], uuid);
    });

    test('an AI event applies its person properties only to its own user',
        () async {
      final server = await LocalPostHogServer.start();
      final client =
          testClient(server, storage: FileStorage(dir.path, worker: worker));
      final prepared = client.prepareEvent(r'$ai_generation', properties: {
        r'$set': {'email': 'user@example.com'},
      })!;

      // The worker measures the event only after reset() has run.
      final uuid = client.captureAiPrepared(r'$ai_generation', prepared);
      client.reset();
      expect(await uuid, isNotNull);
      client.capture('next');
      await client.flush();

      final next = server.batchRequests.single.events.single;
      expect((next['options']! as Map)['process_person_profile'], isFalse);
    });
  });
}
