// Barrel file — re-exports all type definitions for internal use.
export 'config.dart';
export 'feature_flags.dart';
export 'http.dart';
export 'logger.dart';
export 'persistence.dart';

/// Group properties map — values must be non-null primitives.
typedef PostHogGroupProperties = Map<String, Object>;

/// Remote config response (internal).
class PostHogRemoteConfig {
  final bool? hasFeatureFlags;

  const PostHogRemoteConfig({this.hasFeatureFlags});

  factory PostHogRemoteConfig.fromJson(Map<String, Object?> json) {
    return PostHogRemoteConfig(
      hasFeatureFlags: json['hasFeatureFlags'] as bool?,
    );
  }
}

/// Quota limited feature constants (internal).
class QuotaLimitedFeature {
  static const String featureFlags = 'feature_flags';
}
