import 'dart:async';

/// Runs a single beforeSend [callback] against [record], awaiting an async
/// result. Returns the (possibly modified) record, or `null` to drop it.
///
/// Exceptions propagate so each caller applies its own policy (events continue,
/// logs drop). Shared so both handle sync and async callbacks identically.
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
