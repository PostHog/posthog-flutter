import 'dart:convert';

import 'logger.dart';

/// The capture v1 endpoint for analytics events.
const captureV1Path = '/i/v1/analytics/events';

/// The most serialized event bytes a capture v1 batch carries, so requests
/// stay under proxy and capture body limits.
const captureV1MaxBatchBytes = 5 * 1024 * 1024;

/// The capture v1 endpoint for AI events.
const captureV1AiPath = '/i/v1/ai/events';

/// The default number of AI events kept queued.
const captureAiDefaultMaxQueueSize = 100;

/// The default timeout of an AI request.
const captureAiDefaultTimeout = Duration(seconds: 60);

/// The largest serialized AI event the SDK queues: PostHog's 8 MiB limit on
/// an AI event's properties, plus 64 KiB for the rest of the event.
const captureAiMaxEventBytes = 8 * 1024 * 1024 + 64 * 1024;

/// The most AI event bytes kept queued; the oldest events are dropped
/// first.
const captureAiMaxQueueBytes = 50 * 1024 * 1024;

/// Capture v1 statuses worth retrying. Everything else is terminal,
/// including 3xx; 413 halves the batch instead.
bool isRetriableCaptureV1Status(int status) =>
    status == 404 ||
    status == 408 ||
    status == 429 ||
    status == 500 ||
    status == 502 ||
    status == 503 ||
    status == 504;

/// Legacy event properties and the capture v1 option each one fills.
const legacyOptionProperties = <String, String>{
  r'$cookieless_mode': 'cookieless_mode',
  r'$ignore_sent_at': 'disable_skew_correction',
  r'$product_tour_id': 'product_tour_id',
  r'$process_person_profile': 'process_person_profile',
};

/// Shapes a queued event for capture v1.
///
/// `$session_id` and `$window_id` move to the event root, and `$lib` and
/// `$lib_version` are left out: the server reads them from the
/// `PostHog-Sdk-Info` header.
///
/// The legacy option properties are moved into `options` here, when the
/// request is built, so that events queued by earlier versions are converted
/// too. Each one is always removed from the properties and fills its option
/// only when the event's `options` leave it unset or null. Values are sent
/// as they are: the server validates them.
Map<String, Object?> captureV1Event(
  Map<String, Object?> queued,
  CoreLogger logger,
) {
  final properties = <String, Object?>{
    if (queued['properties'] case final Map stored)
      for (final MapEntry(:key, :value) in stored.entries) '$key': value,
  }
    ..remove(r'$lib')
    ..remove(r'$lib_version');

  final options = <String, Object?>{
    if (queued['options'] case final Map stored)
      for (final MapEntry(:key, :value) in stored.entries) '$key': value,
  };
  for (final MapEntry(key: property, value: option)
      in legacyOptionProperties.entries) {
    if (!properties.containsKey(property)) continue;
    final legacy = properties.remove(property);
    if (legacy != null && options[option] == null) options[option] = legacy;
  }

  final sessionId = _liftString(r'$session_id', properties, logger);
  final windowId = _liftString(r'$window_id', properties, logger);
  return {
    'event': queued['event'],
    'uuid': queued['uuid'],
    'distinct_id': queued['distinct_id'],
    'timestamp': queued['timestamp'],
    if (sessionId != null) 'session_id': sessionId,
    if (windowId != null) 'window_id': windowId,
    if (options.isNotEmpty) 'options': options,
    'properties': properties,
  };
}

/// Removes [key] from [properties] and returns its value when it is a
/// string, an empty one included. Capture v1 rejects the whole request when
/// a root `session_id` or `window_id` is not a string, so any other value is
/// dropped with a warning naming its JSON type, never the value. Null counts
/// as unset.
String? _liftString(
  String key,
  Map<String, Object?> properties,
  CoreLogger logger,
) {
  final value = properties.remove(key);
  if (value == null || value is String) return value as String?;
  logger.warn('Dropping $key: a ${_jsonType(value)} value is not a string.');
  return null;
}

String _jsonType(Object value) => switch (value) {
      bool() => 'bool',
      num() => 'number',
      Map() => 'object',
      List() => 'array',
      _ => value.runtimeType.toString(),
    };

/// The identity of a capture v1 request. A retry of the same events reuses
/// the request id and `created_at`, with the next attempt number.
class CaptureV1Identity {
  CaptureV1Identity({
    required this.uuids,
    required this.requestId,
    required this.createdAt,
    this.attempt = 1,
  });

  /// The events the request carries.
  final Set<String> uuids;
  final String requestId;
  final String createdAt;
  final int attempt;

  /// The identity of the retry of [uuids], the events among [this.uuids]
  /// that are still to be delivered.
  CaptureV1Identity withUuids(Set<String> uuids) => CaptureV1Identity(
        uuids: uuids,
        requestId: requestId,
        createdAt: createdAt,
        attempt: attempt,
      );

  /// The identity of the next attempt to send the same events.
  CaptureV1Identity next() => CaptureV1Identity(
        uuids: uuids,
        requestId: requestId,
        createdAt: createdAt,
        attempt: attempt + 1,
      );
}

/// The uuids among [uuids] that a capture v1 response [body] asks to
/// retry, with how many of them it rejected (`drop` or `limited`) and how
/// many repeated copies of them it dropped (`duplicates_dropped`), or null
/// when the body has no readable per-event results.
///
/// [uuids] holds one entry per event sent, repeats included.
///
/// `ok`, `warning`, `drop`, `limited` and any unknown result are final.
/// An event missing from the results counts as delivered.
({Set<String> retry, int rejected, int duplicates})? captureV1Results(
  String? body,
  Iterable<String> uuids,
) {
  if (body == null) return null;
  final Object? results;
  try {
    final decoded = jsonDecode(body);
    results = decoded is Map ? decoded['results'] : null;
  } on FormatException {
    return null;
  }
  if (results is! Map) return null;
  final batch = uuids.toList(growable: false);
  final retry = <String>{};
  var rejected = 0;
  var duplicates = 0;
  for (final uuid in batch.toSet()) {
    final result = results[uuid];
    switch (result) {
      case {'result': 'retry'}:
        retry.add(uuid);
      case {'result': 'drop' || 'limited'}:
        rejected++;
    }
    // Clamped so a malformed count can't exceed the batch.
    if (result case {'duplicates_dropped': final int dropped}) {
      duplicates += dropped.clamp(0, batch.length);
    }
  }
  return (retry: retry, rejected: rejected, duplicates: duplicates);
}

/// Whether two `Set`s hold the same elements.
bool sameUuids(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
