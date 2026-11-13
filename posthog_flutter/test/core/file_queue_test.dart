import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late Directory dir;
  late LocalPostHogServer server;

  setUp(() async {
    dir = tempDirectory();
    server = await LocalPostHogServer.start();
  });

  DesktopPostHog client({PostHogConfig? config}) =>
      testClient(server, config: config, storage: FileStorage(dir.path));

  test('queueing an event writes one file and rewrites nothing else', () async {
    final posthog = client();
    posthog.identify('user-1');
    posthog.capture('first');
    // Waits for the flags reload identify() started, which stores its answer.
    await posthog.reloadFeatureFlagsAsync();
    final snapshot = File('${dir.path}/posthog_data.json');
    final earlier = DateTime(2000);
    for (final file in [snapshot, ..._queueFiles(dir)]) {
      file.setLastModifiedSync(earlier);
    }

    posthog.capture('second');

    expect(snapshot.lastModifiedSync(), earlier);
    final files = _queueFiles(dir);
    expect([for (final file in files) _eventOf(file)],
        [r'$identify', 'first', 'second']);
    expect(files.where((file) => file.lastModifiedSync() != earlier),
        hasLength(1));
  });

  test('counts the serialized bytes of the queued events', () {
    int size(Map<String, Object?> event) =>
        utf8.encode(jsonEncode(event)).length;
    final first = {'event': 'first', 'padding': 'é' * 10};
    final second = {'event': 'second'};
    final third = {'event': 'third'};
    final storage = FileStorage(dir.path);
    final queue = storage.queue
      ..add(first)
      ..add(second)
      ..add(third);
    expect(queue.byteCount, size(first) + size(second) + size(third));

    queue.removeOldest(1);
    expect(queue.byteCount, size(second) + size(third));

    // Read back from the files by the next process.
    storage.close();
    final next = FileStorage(dir.path);
    addTearDown(next.close);
    final restored = next.queue;
    expect(restored.byteCount, size(second) + size(third));
    restored.remove([now(restored.peek(1)).single.id]);
    expect(restored.byteCount, size(third));
  });

  group('peek with maxBytes', () {
    // Each event serializes to `{"p":"<padding>"}`, 18 bytes here.
    FileEventQueue queueOf(List<String> paddings) {
      final storage = FileStorage(dir.path);
      addTearDown(storage.close);
      final queue = storage.queue;
      for (final padding in paddings) {
        queue.add({'p': padding});
      }
      return queue;
    }

    List<Object?> paddingsOf(List<PostHogQueuedEvent> events) =>
        [for (final queued in events) queued.event['p']];

    test('stops before the event that would pass the limit', () {
      final queue = queueOf(['a' * 10, 'b' * 10, 'c' * 10]);

      expect(paddingsOf(now(queue.peek(10, maxBytes: 18 * 2))),
          ['a' * 10, 'b' * 10]);
    });

    test('returns an event over the limit alone', () {
      final queue = queueOf(['a' * 100, 'b']);

      expect(paddingsOf(now(queue.peek(10, maxBytes: 50))), ['a' * 100]);
    });

    test('counts UTF-8 bytes, not characters', () {
      // 18 characters but 28 bytes each.
      final queue = queueOf(['é' * 10, 'è' * 10]);

      expect(paddingsOf(now(queue.peek(10, maxBytes: 18 * 2))), ['é' * 10]);
    });

    test('does not read the events past the limit', () {
      final queue = queueOf(['a' * 10, 'b' * 10]);
      // Unreadable: a peek that read it would delete it.
      final second = _queueFiles(dir).last..writeAsStringSync('not json');

      expect(paddingsOf(now(queue.peek(10, maxBytes: 18))), ['a' * 10]);
      expect(second.existsSync(), isTrue);
    });
  });

  test('keeps the queue order across a restart', () async {
    final before = client();
    for (var i = 0; i < 50; i++) {
      before.capture('event_$i');
    }
    before.close();

    await client().flush();

    expect(server.eventNames, [for (var i = 0; i < 50; i++) 'event_$i']);
    expect(_queueFiles(dir), isEmpty);
  });

  test('drops the oldest event files once the queue is full', () {
    final api = InProcessPostHogApi()
      ..respond = (_) => const PostHogResponse.dropped();
    fakeAsync((async) {
      final posthog = testClient(api,
          config: testConfig(flushAt: 2, maxQueueSize: 2),
          storage: FileStorage(dir.path));

      for (final event in ['first', 'second', 'third']) {
        posthog.capture(event);
      }
      async.elapse(Duration.zero);

      expect([for (final file in _queueFiles(dir)) _eventOf(file)],
          ['second', 'third']);
    });
  });

  test('limits the restored queue before the first timer without capture', () {
    final before = client();
    for (var i = 0; i < 5; i++) {
      before.capture('event_$i');
    }
    final original = [
      for (final file in _queueFiles(dir).skip(3))
        jsonDecode(file.readAsStringSync()),
    ];
    before.close();

    final api = InProcessPostHogApi();
    fakeAsync((async) {
      testClient(api,
          config: testConfig(maxQueueSize: 2, flushAt: 1),
          storage: FileStorage(dir.path));
      expect([for (final file in _queueFiles(dir)) _eventOf(file)],
          ['event_3', 'event_4']);
      expect(api.requests, isEmpty);
      async.elapse(const Duration(seconds: 30));
      expect(
          [for (final event in api.batchRequests.single.events) event['uuid']],
          [for (final event in original) (event as Map)['uuid']]);
      expect(_queueFiles(dir), isEmpty);
    });
  });

  for (final (capacity, remaining) in [(5, 3), (3, 3), (0, 1)]) {
    test('restores $remaining events with maxQueueSize $capacity', () async {
      final before = client();
      for (var i = 0; i < 3; i++) {
        before.capture('event_$i');
      }
      before.close();
      await client(config: testConfig(maxQueueSize: capacity)).flush();
      expect(server.eventNames,
          [for (var i = 3 - remaining; i < 3; i++) 'event_$i']);
    });
  }

  test('restoring a secondary queue does not remove primary queue events',
      () async {
    final primary = client();
    primary.capture('first');
    primary.capture('second');
    final secondary = client(config: testConfig(maxQueueSize: 1));
    secondary.capture('secondary');
    await secondary.flush();
    expect([for (final file in _queueFiles(dir)) _eventOf(file)],
        ['first', 'second']);
    await primary.flush();
    expect(server.eventNames, ['secondary', 'first', 'second']);
  });

  test('deletes a queued event that cannot be read and sends the others',
      () async {
    final before = client();
    for (final event in ['first', 'second', 'third']) {
      before.capture(event);
    }
    before.close();
    final corrupt = _queueFiles(dir)[1]..writeAsStringSync('{"event": "sec');

    final after = client(config: testConfig(debug: true));
    late Future<void> flushed;
    final lines = printedLines(() => flushed = after.flush());
    await flushed;

    expect(server.eventNames, ['first', 'third']);
    expect(lines, contains(contains('cannot be read')));
    expect(corrupt.existsSync(), isFalse);
  });

  test("two clients on one directory never delete each other's events",
      () async {
    final first = client();
    final second = client();

    first.capture('from first');
    second.capture('from second');
    await first.flush();

    expect(server.eventNames, ['from first']);
    expect(
        [for (final file in _queueFiles(dir)) _eventOf(file)], ['from second']);
  });

  test('an event whose file cannot be written is still sent', () async {
    addTearDown(() => chmod('755', dir.path));
    final posthog = client();
    chmod('555', dir.path);

    posthog.capture('evt');
    await posthog.flush();

    expect(server.eventNames, ['evt']);
    expect(Directory('${dir.path}/posthog_queue').existsSync(), isFalse);
  }, skip: chmodSkip);
}

/// The event files of the queue in [dir], oldest first.
List<File> _queueFiles(Directory dir) {
  final queue = Directory('${dir.path}/posthog_queue');
  if (!queue.existsSync()) return [];
  return queue.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

Object? _eventOf(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map)['event'];
