import 'dart:typed_data';

import '../posthog_event.dart';
import '../util/logging.dart';

/// Runs [callbacks] in order against [event].
///
/// A null return drops the event and skips the rest of the list. A throw drops
/// the event too. With [disableGeoIp], the event keeps `$geoip_disable: true`
/// whatever the callbacks return.
PostHogEvent? applyBeforeSend(
  List<PostHogEvent? Function(PostHogEvent)> callbacks,
  PostHogEvent event, {
  bool disableGeoIp = false,
}) {
  for (final callback in callbacks) {
    try {
      final result = callback(event);
      if (result == null) return null;
      event = result;
    } catch (e) {
      printIfDebug(
        '[PostHog] Warning: beforeSend callback threw an exception; dropping event: $e',
      );
      return null;
    }
  }
  if (disableGeoIp) {
    event.properties = {...?event.properties, r'$geoip_disable': true};
  }
  return event;
}

/// A deep copy of [value] with the collection types callbacks get on every
/// platform except web: callbacks commonly cast `$exception_list` to
/// `List<Map<String, dynamic>>`, and a failed cast drops the event. Copying
/// also keeps a callback that edits a nested value in place from changing
/// registered properties or options in storage.
Object? copyForBeforeSend(Object? value) {
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) return value;
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: copyForBeforeSend(entry.value),
    };
  }
  if (value is List && value is! TypedData) {
    final items = value.map(copyForBeforeSend).toList();
    return items.isNotEmpty && items.every((i) => i is Map<String, dynamic>)
        ? List<Map<String, dynamic>>.from(items)
        : items;
  }
  return value;
}
