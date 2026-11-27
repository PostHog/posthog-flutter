import 'dart:async';

import 'package:posthog_flutter/src/core/queue_worker.dart';

/// Core tests drive time with fake timers, in which messages from the
/// queue's background isolate never arrive, so their queues run the worker's
/// jobs inline. `queue_worker_test.dart` covers the background isolate.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  QueueWorker.defaultWorker = QueueWorker.inline;
  await testMain();
}
