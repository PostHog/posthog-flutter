import 'dart:collection';
import 'dart:convert';

/// Asserts that a value is a non-empty string, throwing if not.
void assertNotEmpty(String? value, String message) {
  if (value == null || value.trim().isEmpty) {
    throw ArgumentError(message);
  }
}

/// Removes trailing slashes from a URL.
String removeTrailingSlash(String url) {
  return url.replaceAll(RegExp(r'/+$'), '');
}

/// Returns current time as ISO 8601 string.
String currentISOTime() => DateTime.now().toUtc().toIso8601String();

/// Retries an async function with configurable options.
Future<T> retriable<T>(
  Future<T> Function() fn, {
  required int retryCount,
  required int retryDelay,
  required bool Function(Object) retryCheck,
}) async {
  Object? lastError;

  for (var i = 0; i < retryCount + 1; i++) {
    if (i > 0) {
      await Future.delayed(Duration(milliseconds: retryDelay));
    }

    try {
      return await fn();
    } catch (e) {
      lastError = e;
      if (!retryCheck(e)) {
        rethrow;
      }
    }
  }

  throw lastError!;
}

/// Returns a single-entry map if [value] is non-null, empty map otherwise.
Map<String, Object?> maybeAdd(String key, Object? value) {
  if (value != null) {
    return {key: value};
  }
  return {};
}

/// Recursively sorts all keys in a map for deterministic serialization.
/// Uses [SplayTreeMap] which maintains keys in sorted order.
Object? deepSortKeys(Object? value) {
  if (value == null || value is! Map) {
    if (value is List) {
      return value.map(deepSortKeys).toList();
    }
    return value;
  }

  final sorted = SplayTreeMap<String, Object?>.from(
    value as Map<String, Object?>,
  );
  return sorted.map((k, v) => MapEntry(k, deepSortKeys(v)));
}

/// Creates a deterministic hash string from distinct_id and person properties.
String getPersonPropertiesHash(
  String distinctId,
  Map<String, Object?>? userPropertiesToSet,
  Map<String, Object?>? userPropertiesToSetOnce,
) {
  return jsonEncode({
    'distinct_id': distinctId,
    'userPropertiesToSet':
        userPropertiesToSet != null ? deepSortKeys(userPropertiesToSet) : null,
    'userPropertiesToSetOnce': userPropertiesToSetOnce != null
        ? deepSortKeys(userPropertiesToSetOnce)
        : null,
  });
}
