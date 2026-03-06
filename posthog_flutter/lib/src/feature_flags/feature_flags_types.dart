import 'dart:convert';

/// Detailed information about a single feature flag evaluation from the v2 API.
class FeatureFlagDetail {
  final String key;
  final bool enabled;
  final String? variant;
  final EvaluationReason? reason;
  final FeatureFlagMetadata? metadata;
  final bool? failed;

  const FeatureFlagDetail({
    required this.key,
    required this.enabled,
    this.variant,
    this.reason,
    this.metadata,
    this.failed,
  });

  factory FeatureFlagDetail.fromJson(String key, Map<String, dynamic> json) {
    return FeatureFlagDetail(
      key: key,
      enabled: json['enabled'] as bool? ?? false,
      variant: json['variant'] as String?,
      reason: json['reason'] != null
          ? EvaluationReason.fromJson(
              Map<String, dynamic>.from(json['reason'] as Map))
          : null,
      metadata: json['metadata'] != null
          ? FeatureFlagMetadata.fromJson(
              Map<String, dynamic>.from(json['metadata'] as Map))
          : null,
      failed: json['failed'] as bool?,
    );
  }

  /// Returns the effective value of this flag.
  /// For multivariate flags, returns the variant string.
  /// For boolean flags, returns the enabled bool.
  Object? get value => variant ?? enabled;

  @override
  String toString() =>
      'FeatureFlagDetail(key: $key, enabled: $enabled, variant: $variant, failed: $failed)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeatureFlagDetail &&
        other.key == key &&
        other.enabled == enabled &&
        other.variant == variant &&
        other.failed == failed;
  }

  @override
  int get hashCode => Object.hash(key, enabled, variant, failed);
}

/// Metadata about a feature flag.
class FeatureFlagMetadata {
  final int? id;
  final int? version;
  final String? description;
  final Object? payload;

  const FeatureFlagMetadata({
    this.id,
    this.version,
    this.description,
    this.payload,
  });

  factory FeatureFlagMetadata.fromJson(Map<String, dynamic> json) {
    return FeatureFlagMetadata(
      id: json['id'] as int?,
      version: json['version'] as int?,
      description: json['description'] as String?,
      payload: _parsePayload(json['payload']),
    );
  }

  static Object? _parsePayload(Object? raw) {
    if (raw == null) return null;
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }
}

/// The reason a feature flag was evaluated to its current value.
class EvaluationReason {
  final String? code;
  final int? conditionIndex;
  final String? description;

  const EvaluationReason({
    this.code,
    this.conditionIndex,
    this.description,
  });

  factory EvaluationReason.fromJson(Map<String, dynamic> json) {
    return EvaluationReason(
      code: json['code'] as String?,
      conditionIndex: json['condition_index'] as int?,
      description: json['description'] as String?,
    );
  }
}

/// Parsed response from the `/flags/?v=2` API endpoint.
class PostHogFlagsResponse {
  final Map<String, FeatureFlagDetail> flags;
  final bool errorsWhileComputingFlags;
  final List<String> quotaLimited;
  final String? requestId;
  final int? evaluatedAt;

  const PostHogFlagsResponse({
    required this.flags,
    this.errorsWhileComputingFlags = false,
    this.quotaLimited = const [],
    this.requestId,
    this.evaluatedAt,
  });

  /// Returns a map of flag key → value (variant string or enabled bool),
  /// matching the legacy `featureFlags` format.
  Map<String, Object> get featureFlags {
    final result = <String, Object>{};
    for (final entry in flags.entries) {
      if (entry.value.enabled) {
        result[entry.key] = entry.value.variant ?? true;
      }
    }
    return result;
  }

  /// Returns a map of flag key → payload, for flags that have payloads.
  Map<String, Object> get featureFlagPayloads {
    final result = <String, Object>{};
    for (final entry in flags.entries) {
      final payload = entry.value.metadata?.payload;
      if (payload != null) {
        result[entry.key] = payload;
      }
    }
    return result;
  }
}

/// Error types for feature flag requests.
enum FeatureFlagRequestErrorType {
  networkError,
  httpError,
  parseError,
}

/// Error from a feature flag request.
class FeatureFlagRequestError {
  final FeatureFlagRequestErrorType type;
  final String message;
  final int? statusCode;

  const FeatureFlagRequestError({
    required this.type,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() =>
      'FeatureFlagRequestError($type: $message${statusCode != null ? ', status: $statusCode' : ''})';
}

/// Result of a feature flag fetch operation.
sealed class GetFlagsResult {
  const GetFlagsResult();
}

class GetFlagsSuccess extends GetFlagsResult {
  final PostHogFlagsResponse response;
  const GetFlagsSuccess(this.response);
}

class GetFlagsFailure extends GetFlagsResult {
  final FeatureFlagRequestError error;
  const GetFlagsFailure(this.error);
}
