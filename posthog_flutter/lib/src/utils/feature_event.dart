import '../util/logging.dart';

/// The `$feature_view` / `$feature_interaction` capture as posthog-ios builds
/// it, or null when the flag has no value and the event is skipped.
({Map<String, Object> properties, Map<String, Object> userProperties})?
    featureEvent(String event, String flag, Object? variant) {
  if (variant == null) {
    printIfDebug(
        '[PostHog] $event skipped: feature flag "$flag" has no value.');
    return null;
  }
  return (
    properties: {
      'feature_flag': flag,
      if (variant is String) 'feature_flag_variant': variant,
    },
    userProperties: {'$event/$flag': variant},
  );
}
