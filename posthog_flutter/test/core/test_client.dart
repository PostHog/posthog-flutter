import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
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
/// attaches [context] and [timezone] to its events.
DesktopPostHog testClient(
  PostHogApiFake api, {
  PostHogConfig? config,
  FileStorage? storage,
  Map<String, Object?> context = const {},
  String? timezone,
}) {
  final client = api.connect(
    () => DesktopPostHog(
      (config ?? testConfig())..host = api.url,
      storage: storage ?? tempStorage(),
      staticContext: context,
      timezone: timezone,
    ),
  );
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

/// The queued event messages, oldest first.
List<Map<String, Object?>> getQueue(FileStorage storage) => [
      for (final queued in storage.queue.peek(storage.queue.length))
        queued.event,
    ];

/// The queued event message at [index].
Map<String, Object?> queuedMessage(FileStorage storage, int index) =>
    getQueue(storage)[index];

/// The properties of the queued event message at [index].
Map<String, Object?> queuedProps(FileStorage storage, int index) {
  return queuedMessage(storage, index)['properties'] as Map<String, Object?>;
}

/// The names of the queued events, oldest first.
List<Object?> queuedEvents(FileStorage storage) =>
    [for (final message in getQueue(storage)) message['event']];

/// The properties of the only queued event named [event].
Map<String, Object?> queuedPropsOf(FileStorage storage, String event) {
  final message =
      getQueue(storage).singleWhere((message) => message['event'] == event);
  return message['properties'] as Map<String, Object?>;
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
