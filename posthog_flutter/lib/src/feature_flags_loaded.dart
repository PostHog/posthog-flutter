/// The feature flags passed to [PostHogConfig.onFeatureFlags] and returned by
/// [Posthog.reloadFeatureFlags].
///
/// Only enabled flags are included. When the latest load failed,
/// [errorsLoading] is `true` and the flags are the last known values, which
/// can be empty.
///
/// **Example:**
/// ```dart
/// final config = PostHogConfig('<project_token>')
///   ..onFeatureFlags = (loaded) {
///     if (loaded.errorsLoading) {
///       // The values are the last known (cached) flags.
///     }
///     if (loaded.variants['new-checkout'] == 'test') {
///       // Show the test variant.
///     }
///   };
/// ```
class PostHogFeatureFlagsLoaded {
  /// The keys of the enabled feature flags.
  List<String> get flags => List.unmodifiable(variants.keys);

  /// The values of the enabled feature flags, keyed by flag key.
  ///
  /// A value is `true` for an enabled boolean flag, or the variant [String]
  /// for a multivariate flag. Disabled flags are not included.
  final Map<String, Object> variants;

  /// Whether the latest attempt to load feature flags failed.
  ///
  /// When it did, [flags] and [variants] hold the last known values.
  final bool errorsLoading;

  /// Creates the loaded feature flags from [variants], keeping only enabled
  /// flags: `true`, or a non-empty variant string.
  PostHogFeatureFlagsLoaded({
    required Map<String, Object?> variants,
    required this.errorsLoading,
  }) : variants = Map.unmodifiable({
          for (final MapEntry(:key, :value) in variants.entries)
            if (value == true || (value is String && value.isNotEmpty))
              key: value!,
        });

  @override
  String toString() =>
      'PostHogFeatureFlagsLoaded(variants: $variants, errorsLoading: $errorsLoading)';
}
