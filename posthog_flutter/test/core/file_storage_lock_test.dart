import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/persistence.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = tempDirectory();
  });

  FileStorage storage() {
    final storage = FileStorage(dir.path);
    addTearDown(storage.close);
    return storage;
  }

  String? storedDistinctId() => FileStorage(dir.path)
      .getProperty<String>(PostHogPersistedProperty.distinctId);

  test('a second storage on the directory keeps its changes in memory', () {
    final first = storage();
    final second = storage();

    first.setProperty(PostHogPersistedProperty.distinctId, 'first-user');
    second.setProperty(PostHogPersistedProperty.distinctId, 'second-user');

    expect(second.getProperty<String>(PostHogPersistedProperty.distinctId),
        'second-user');
    expect(storedDistinctId(), 'first-user');
  });

  test('a client on a directory in use logs it once and queues as usual',
      () async {
    final server = await LocalPostHogServer.start();
    testClient(server, storage: storage());

    late DesktopPostHog second;
    final lines = printedLines(() {
      second = testClient(server,
          config: testConfig(debug: true), storage: storage());
      second
        ..identify('second-user')
        ..capture('from second');
    });

    expect(lines.where((line) => line.contains('Another PostHog client')),
        hasLength(1));
    expect(second.getDistinctId(), 'second-user');
    expect(storedDistinctId(), isNull,
        reason: 'the identity on disk belongs to the first client');
    expect(_queuedOnDisk(dir), [r'$identify', 'from second']);
  });

  test('the next storage takes over once the holder is closed', () {
    final first = storage()
      ..setProperty(PostHogPersistedProperty.distinctId, 'first-user');
    final second = storage()
      ..setProperty(PostHogPersistedProperty.distinctId, 'second-user');

    first.close();
    storage().setProperty(PostHogPersistedProperty.distinctId, 'third-user');
    second.setProperty(PostHogPersistedProperty.distinctId, 'second-again');

    expect(storedDistinctId(), 'third-user');
  });

  test('a closed client releases the directory', () async {
    final server = await LocalPostHogServer.start();
    testClient(server, storage: storage()).close();

    final next = testClient(server, storage: storage());
    next.identify('next-user');

    expect(storedDistinctId(), 'next-user');
  });

  test('a directory locked by another process is left to it', () async {
    final releaseLock = await _lockInAnotherProcess(dir);
    addTearDown(releaseLock);

    final blocked = storage()
      ..setProperty(PostHogPersistedProperty.distinctId, 'blocked-user');
    blocked.queue.add({'event': 'queued meanwhile'});

    expect(storedDistinctId(), isNull);
    expect(_queuedOnDisk(dir), ['queued meanwhile']);

    await releaseLock();
    storage().setProperty(PostHogPersistedProperty.distinctId, 'next-user');

    expect(storedDistinctId(), 'next-user');
  },
      skip: Platform.isMacOS
          ? 'FileStorage runs on Linux and Windows, and tells a lock held '
              'by another process by their error codes'
          : false);
}

/// The names of the events queued on disk in [dir], oldest first.
List<Object?> _queuedOnDisk(Directory dir) {
  final files = Directory('${dir.path}/posthog_queue')
      .listSync()
      .whereType<File>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      (jsonDecode(file.readAsStringSync()) as Map)['event'],
  ];
}

/// Locks [dir] the way [FileStorage] does, from a separate process. Returns
/// a function that ends that process, releasing the lock.
Future<Future<void> Function()> _lockInAnotherProcess(Directory dir) async {
  final script = File('${dir.path}/lock_holder.dart')..writeAsStringSync(r'''
import 'dart:io';

void main(List<String> args) {
  File(args.single)
      .openSync(mode: FileMode.append)
      .lockSync(FileLock.exclusive);
  print('locked');
  stdin.listen(null, onDone: () => exit(0));
}
''');
  final process = await Process.start(_dartExecutable(),
      [script.path, '${dir.path}${Platform.pathSeparator}posthog.lock']);
  await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .firstWhere((line) => line == 'locked');

  var released = false;
  return () async {
    if (released) return;
    released = true;
    await process.stdin.close();
    await process.exitCode;
  };
}

/// The Dart VM of the Flutter SDK running the tests: `flutter test` runs them
/// in flutter_tester, which cannot run a script of its own.
String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) fail('FLUTTER_ROOT is not set; run `flutter test`');
  final sep = Platform.pathSeparator;
  final dart = Platform.isWindows ? 'dart.exe' : 'dart';
  return '$flutterRoot${sep}bin${sep}cache${sep}dart-sdk${sep}bin$sep$dart';
}
