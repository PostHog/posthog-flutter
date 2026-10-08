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

  /// Creates a feature flag evaluation result.
  ///
  /// The [key] is the feature flag key that was evaluated.
  ///
  /// The [enabled] value is the boolean result for boolean flags. For
  /// multivariate flags, it is `true` when the flag evaluates to a variant and
  /// `false` when it does not match.
  ///
  /// The optional [variant] is the variant key for multivariate flags.
  ///
  /// The optional [payload] is the JSON payload configured for the matched flag
  /// or variant.
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
}
