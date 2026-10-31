import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/logger.dart';
import 'package:posthog_flutter/src/core/queue_worker.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';

import '../posthog_api_fake.dart';

/// Config tuned for tests: no preload unless asked for, and a flushAt high
/// enough that flushes only happen when a test asks for them.
PostHogConfig testConfig({
  bool preloadFeatureFlags = false,
  int flushAt = 100,
  int maxBatchSize = 100,
  int maxQueueSize = 1000,
  Duration flushInterval = const Duration(seconds: 30),
  bool optOut = false,
  bool debug = false,
  PostHogPersonProfiles personProfiles = PostHogPersonProfiles.identifiedOnly,
  PostHogBootstrapConfig? bootstrap,
}) =>
    PostHogConfig('k')
      ..flushAt = flushAt
      ..maxBatchSize = maxBatchSize
      ..maxQueueSize = maxQueueSize
      ..flushInterval = flushInterval
      ..preloadFeatureFlags = preloadFeatureFlags
      ..optOut = optOut
      ..debug = debug
      ..personProfiles = personProfiles
      ..bootstrap = bootstrap;

/// A new temporary directory, deleted at the end of the test.
Directory tempDirectory() {
  final dir = Directory.systemTemp.createTempSync('posthog_core');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// A storage in a new temporary directory.
FileStorage tempStorage() => FileStorage(tempDirectory().path);

/// A client of [api] with [config], closed at the end of the test. It keeps
/// its state in [storage], a new temporary directory by default, and
/// attaches [context] and [timezone] to its events. Its backoff has no
/// jitter unless [jitterUnit] says otherwise, so retries come 1, 2, 4, 8, 16
/// and then 30 seconds apart.
DesktopPostHog testClient(
  PostHogApiFake api, {
  PostHogConfig? config,
  FileStorage? storage,
  Map<String, Object?> context = const {},
  String? timezone,
  double jitterUnit = 0.5,
}) {
  final client = api.connect(
    () => DesktopPostHog(
      (config ?? testConfig())..host = api.url,
      storage: storage ?? tempStorage(),
      staticContext: context,
      timezone: timezone,
    ),
  );
  client.jitterUnit = () => jitterUnit;
  addTearDown(client.close);
  return client;
}

/// The number of `/flags/` requests [client] sends for [action].
///
/// A reload asked for runs once the one in flight is done, so one before
/// [action] and one after it bracket the requests of [action]; they are
/// left out of the count.
Future<int> flagsRequestsFor(
  DesktopPostHog client,
  PostHogApiFake api,
  void Function() action,
) async {
  await client.reloadFeatureFlagsAsync();
  final before = api.flagsRequests.length;
  action();
  await client.reloadFeatureFlagsAsync();
  return api.flagsRequests.length - before - 1;
}

/// The value of [future], which an inline [QueueWorker] completes right
/// away.
T now<T>(Future<T> future) {
  late T value;
  var done = false;
  future.then((result) {
    value = result;
    done = true;
  });
  if (!done) throw StateError('The future did not complete synchronously.');
  return value;
}

/// The queued event messages, oldest first.
List<Map<String, Object?>> getQueue(FileStorage storage) => [
      for (final queued in now(storage.queue.peek(storage.queue.length)))
        queued.event,
    ];

/// The queued event message at [index].
Map<String, Object?> queuedMessage(FileStorage storage, int index) =>
    getQueue(storage)[index];

/// The properties of the queued event message at [index].
Map<String, Object?> queuedProps(FileStorage storage, int index) {
  return queuedMessage(storage, index)['properties'] as Map<String, Object?>;
}

/// The capture v1 options of the queued event message at [index], empty
/// when it has none.
Map<String, Object?> queuedOptions(FileStorage storage, int index) =>
    Map<String, Object?>.from(
        (queuedMessage(storage, index)['options'] ?? const {}) as Map);

/// The names of the queued events, oldest first.
List<Object?> queuedEvents(FileStorage storage) =>
    [for (final message in getQueue(storage)) message['event']];

/// The properties of the only queued event named [event].
Map<String, Object?> queuedPropsOf(FileStorage storage, String event) {
  final message =
      getQueue(storage).singleWhere((message) => message['event'] == event);
  return message['properties'] as Map<String, Object?>;
}

/// Runs jobs like [QueueWorker.inline], except that writes and deletes wait
/// for [writeGate] and [deleteGate] while those are set.
class GatedWorker implements QueueWorker {
  @override
  CoreLogger? logger;

  final _inline = QueueWorker.inline();
  Completer<void>? writeGate;
  Completer<void>? deleteGate;
  var writes = 0;
  var deletes = 0;

  @override
  Future<QueueWriteResult> write(
    String? path,
    Map<String, Object?> event, {
    int? maxBytes,
  }) {
    writes++;
    final gate = writeGate;
    return gate == null
        ? _inline.write(path, event, maxBytes: maxBytes)
        : gate.future
            .then((_) => _inline.write(path, event, maxBytes: maxBytes));
  }

  @override
  Future<List<String>> delete(List<String> paths) {
    deletes++;
    // Like the real worker, a delete never overtakes an earlier write.
    final gates = [writeGate, deleteGate].nonNulls.map((gate) => gate.future);
    return gates.isEmpty
        ? _inline.delete(paths)
        : Future.wait(gates).then((_) => _inline.delete(paths));
  }

  @override
  Future<List<QueueReadResult>> read(List<String> paths) => _inline.read(paths);

  @override
  Future<EncodedBody> encodeBody(Object? body, {required bool gzip}) =>
      _inline.encodeBody(body, gzip: gzip);

  @override
  bool get runsInBackground => false;

  @override
  void kill() {}
}

/// Skip reason for tests that simulate IO failures with POSIX permissions.
final chmodSkip =
    Platform.isWindows ? 'simulates IO failures via POSIX chmod' : false;

/// Applies [mode] via chmod, failing the test if the probe cannot be set up.
void chmod(String mode, String path) {
  final result = Process.runSync('chmod', [mode, path]);
  expect(result.exitCode, 0,
      reason: 'chmod $mode must succeed for the probe to prove anything');
}

/// Runs [body] and returns the lines it logged through [debugPrint].
List<String> printedLines(void Function() body) {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
  try {
    body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}
