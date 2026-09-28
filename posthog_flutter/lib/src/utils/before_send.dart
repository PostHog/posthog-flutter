import 'dart:async';

import '../posthog_event.dart';
import '../util/logging.dart';

/// Runs a single beforeSend [callback] against [record], awaiting an async
/// result. Returns the (possibly modified) record, or `null` to drop it.
///
/// A throw propagates. [applyBeforeSend] is the event policy: it drops the
/// event. Log capture drops the record in its own loop.
Future<T?> runBeforeSend<T>(
  FutureOr<T?> Function(T) callback,
  T record,
) async {
  final result = callback(record);
  if (result is Future<T?>) {
    return await result;
  }
  return result;
}

/// Runs [callbacks] in order against [event].
///
/// A null return drops the event and skips the rest of the list. A throw drops
/// the event too.
Future<PostHogEvent?> applyBeforeSend(
  List<FutureOr<PostHogEvent?> Function(PostHogEvent)> callbacks,
  PostHogEvent event,
) async {
  if (callbacks.isEmpty) return event;

  for (final callback in callbacks) {
    try {
      final result = await runBeforeSend<PostHogEvent>(callback, event);
      if (result == null) return null;
      event = result;
    } catch (e) {
      printIfDebug(
        '[PostHog] Warning: beforeSend callback threw an exception; dropping event: $e',
      );
      return null;
    }
  }
  return event;
}
