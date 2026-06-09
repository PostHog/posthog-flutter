import 'dart:async';

import 'package:posthog_flutter/src/util/logging.dart';

/// Applies a single beforeSend [callback] to [record] safely.
///
/// Returns `null` if the callback drops the record, otherwise returns the
/// (possibly modified) record. Handles both synchronous and asynchronous
/// callbacks via `FutureOr`. A callback that throws is contained: the exception
/// is logged and the pre-callback [record] is returned so the chain continues
/// with the remaining callbacks.
///
/// Shared by the event path (`PosthogFlutterIO.capture`) and the logs path
/// (`Posthog.captureLog`) so both keep identical exception-handling semantics.
Future<T?> applyBeforeSend<T>(
  FutureOr<T?> Function(T) callback,
  T record,
) async {
  try {
    final result = callback(record);
    if (result is Future<T?>) {
      return await result;
    }
    return result;
  } catch (e) {
    printIfDebug('[PostHog] beforeSend callback threw exception: $e');
    return record;
  }
}
