import '../util/logging.dart';
import 'property_normalizer.dart';

/// The known per-event option keys and the legacy event property each one
/// replaces.
const Map<String, String> _legacyPropertyForOption = {
  'process_person_profile': r'$process_person_profile',
  'cookieless_mode': r'$cookieless_mode',
  'disable_skew_correction': r'$ignore_sent_at',
  'product_tour_id': r'$product_tour_id',
};

/// Returns a copy of [options] without null values, normalized for the
/// platform channel, or null when nothing is left. A null value means unset.
Map<String, Object>? cleanEventOptions(Map<String, Object?>? options) {
  if (options == null) return null;
  final cleaned = PropertyNormalizer.normalize(options);
  if (cleaned.isEmpty) return null;
  return Map<String, Object>.from(cleaned);
}

/// Converts [options] to the legacy event properties for posthog-js, which
/// has no options field.
///
/// Known keys become their `$` property. Other keys have no legacy property,
/// so they are dropped with a debug log naming [method].
Map<String, Object> eventOptionsToLegacyProperties(
  Map<String, Object?>? options, {
  required String method,
}) {
  final cleaned = cleanEventOptions(options);
  if (cleaned == null) return const {};
  final properties = <String, Object>{};
  for (final entry in cleaned.entries) {
    final legacyKey = _legacyPropertyForOption[entry.key];
    if (legacyKey != null) {
      properties[legacyKey] = entry.value;
    } else {
      printIfDebug(
        '[PostHog] $method option "${entry.key}" is not supported on this '
        'platform and was dropped.',
      );
    }
  }
  return properties;
}
