/// Represents the result of a feature flag evaluation.
///
/// Contains the flag key, whether it's enabled, the variant (for multivariate flags),
/// and any associated payload.
class PostHogFeatureFlagResult {
  /// The feature flag key.
  final String key;

  /// Whether the flag is enabled.
  ///
  /// For boolean flags, this is the flag value.
  /// For multivariate flags, this is true when the flag evaluates to any variant.
  final bool enabled;

  /// The variant key for multivariate flags, or null for boolean flags.
  final String? variant;

  /// The JSON payload associated with the flag, if any.
  final Object? payload;

  const PostHogFeatureFlagResult({
    required this.key,
    required this.enabled,
    this.variant,
    this.payload,
  });

  @override
  String toString() {
    return 'PostHogFeatureFlagResult(key: $key, enabled: $enabled, variant: $variant, payload: $payload)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PostHogFeatureFlagResult &&
        other.key == key &&
        other.enabled == enabled &&
        other.variant == variant;
  }

  @override
  int get hashCode => Object.hash(key, enabled, variant);

  /// Creates a [PostHogFeatureFlagResult] from a native SDK response map.
  ///
  /// The [map] should contain: key, enabled, variant, payload.
  /// Falls back to [fallbackKey] if the map doesn't include a key.
  /// Returns null if [result] is null or not a Map.
  static PostHogFeatureFlagResult? fromMap(Object? result, String fallbackKey) {
    if (result == null) return null;
    if (result is! Map) return null;

    return PostHogFeatureFlagResult(
      key: result['key'] as String? ?? fallbackKey,
      enabled: result['enabled'] as bool? ?? false,
      variant: result['variant'] as String?,
      payload: result['payload'],
    );
  }
}
