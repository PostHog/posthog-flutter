import 'dart:collection';
import 'dart:convert';

import '../logger.dart';

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
  required Duration retryDelay,
  required bool Function(Object) retryCheck,
}) async {
  Object? lastError;

  for (var i = 0; i < retryCount + 1; i++) {
    if (i > 0) {
      await Future.delayed(retryDelay);
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

/// Returns [value] as a new structure that `jsonEncode` accepts.
///
/// A [DateTime] becomes its ISO 8601 string in UTC and a [Uri] its string.
/// Other values JSON cannot represent are converted like `jsonEncode` does,
/// through their `toJson()`, or else sent as their `toString()` with a
/// warning to [logger]. Map keys become strings. With [dropNullMembers],
/// null-valued map entries are left out at every level, while list
/// elements keep their positions.
Object? toJsonValue(Object? value, CoreLogger logger,
    {bool dropNullMembers = false}) {
  // The maps and lists being converted: one that contains itself goes to
  // the fallback below, which reports it, instead of recursing forever.
  final converting = Set<Object>.identity();

  Object? convert(Object? value) {
    switch (value) {
      case null || bool() || String() || int() || double(isFinite: true):
        return value;
      case final DateTime date:
        return date.toUtc().toIso8601String();
      case final Uri uri:
        return uri.toString();
      case final Map map:
        if (!converting.add(map)) break;
        try {
          return {
            for (final MapEntry(:key, value: member) in map.entries)
              if (member != null || !dropNullMembers) '$key': convert(member),
          };
        } finally {
          converting.remove(map);
        }
      case final List list:
        if (!converting.add(list)) break;
        try {
          return [for (final element in list) convert(element)];
        } finally {
          converting.remove(list);
        }
    }
    try {
      return convert(jsonDecode(jsonEncode(value)));
    } on JsonUnsupportedObjectError {
      logger.warn('Sending a property value of type ${value.runtimeType} as '
          'its toString(): it cannot be JSON-encoded.');
      return value.toString();
    }
  }

  return convert(value);
}

/// [toJsonValue] for a map, typed as the JSON object it becomes.
Map<String, Object?> toJsonMap(Map<Object?, Object?> map, CoreLogger logger) =>
    toJsonValue(map, logger) as Map<String, Object?>;

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
  if (value is Map) {
    // Nested maps often arrive untyped (map literals, jsonDecode output),
    // so entries are copied over instead of casting the whole map.
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted['${entry.key}'] = deepSortKeys(entry.value);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(deepSortKeys).toList();
  }
  return value;
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
