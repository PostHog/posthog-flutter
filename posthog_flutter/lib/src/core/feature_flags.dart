import 'dart:convert' show jsonDecode;

/// Feature flag value — either a [bool] or a [String] variant.
///
/// Dart has no union types, so this is typed as [Object].
/// In practice, values are always `bool` or `String`.
typedef PostHogFeatureFlagValue = Object;

/// Decodes a flag payload, which is stored as serialized JSON.
///
/// A payload that is not valid JSON (an empty string included) is no
/// payload: null is returned and the error goes to [onMalformed].
Object? parsePayload(String serialized,
    {required void Function(FormatException error) onMalformed}) {
  try {
    return jsonDecode(serialized);
  } on FormatException catch (e) {
    onMalformed(e);
    return null;
  }
}

/// Feature flag detail from the v2 API.
class PostHogFeatureFlagDetail {
  final String key;
  final bool enabled;
  final String? variant;
  final PostHogEvaluationReason? reason;
  final PostHogFeatureFlagMetadata? metadata;
  final bool? failed;

  const PostHogFeatureFlagDetail({
    required this.key,
    required this.enabled,
    this.variant,
    this.reason,
    this.metadata,
    this.failed,
  });

  Map<String, Object?> toJson() => {
        'key': key,
        'enabled': enabled,
        if (variant != null) 'variant': variant,
        if (reason != null) 'reason': reason!.toJson(),
        if (metadata != null) 'metadata': metadata!.toJson(),
        if (failed != null) 'failed': failed,
      };

  factory PostHogFeatureFlagDetail.fromJson(Map<String, Object?> json) {
    return PostHogFeatureFlagDetail(
      key: json['key'] as String,
      enabled: json['enabled'] as bool,
      variant: json['variant'] as String?,
      reason: json['reason'] != null
          ? PostHogEvaluationReason.fromJson(
              json['reason'] as Map<String, Object?>)
          : null,
      metadata: json['metadata'] != null
          ? PostHogFeatureFlagMetadata.fromJson(
              json['metadata'] as Map<String, Object?>)
          : null,
      failed: json['failed'] as bool?,
    );
  }

  /// Parses a raw flags map, skipping entries whose shape is not understood
  /// (reported via [onMalformed]) so one bad flag cannot take down the rest.
  static Map<String, PostHogFeatureFlagDetail> parseAll(
    Map<String, Object?> raw, {
    required void Function(String key, Object error) onMalformed,
  }) {
    final flags = <String, PostHogFeatureFlagDetail>{};
    for (final entry in raw.entries) {
      try {
        flags[entry.key] = PostHogFeatureFlagDetail.fromJson(
            (entry.value as Map).cast<String, Object?>());
      } catch (e) {
        onMalformed(entry.key, e);
      }
    }
    return flags;
  }
}

/// Metadata for a feature flag.
class PostHogFeatureFlagMetadata {
  final int? id;
  final int? version;
  final String? payload;

  /// Whether the flag is linked to an experiment, or null when the server
  /// did not say.
  final bool? hasExperiment;

  const PostHogFeatureFlagMetadata({
    this.id,
    this.version,
    this.payload,
    this.hasExperiment,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'payload': payload,
        'has_experiment': hasExperiment,
      };

  factory PostHogFeatureFlagMetadata.fromJson(Map<String, Object?> json) {
    final hasExperiment = json['has_experiment'];
    return PostHogFeatureFlagMetadata(
      id: json['id'] as int?,
      version: json['version'] as int?,
      payload: json['payload'] as String?,
      // An unexpected shape reads as unknown rather than rejecting the flag.
      hasExperiment: hasExperiment is bool ? hasExperiment : null,
    );
  }
}

/// Evaluation reason for a feature flag.
class PostHogEvaluationReason {
  final String? code;
  final String? description;

  const PostHogEvaluationReason({this.code, this.description});

  Map<String, Object?> toJson() => {
        'code': code,
        'description': description,
      };

  factory PostHogEvaluationReason.fromJson(Map<String, Object?> json) {
    return PostHogEvaluationReason(
      code: json['code'] as String?,
      description: json['description'] as String?,
    );
  }
}

/// Feature flags response from the server (v2 format).
class PostHogFlagsResponse {
  /// The v2 flags map — the source of truth.
  final Map<String, PostHogFeatureFlagDetail> flags;
  final bool errorsWhileComputingFlags;
  final List<String>? quotaLimited;
  final String? requestId;
  final int? evaluatedAt;

  /// Whether the server asks for minimal `$feature_flag_called` events for
  /// flags that are not linked to an experiment.
  final bool minimalFlagCalledEvents;

  const PostHogFlagsResponse({
    this.flags = const {},
    this.errorsWhileComputingFlags = false,
    this.quotaLimited,
    this.requestId,
    this.evaluatedAt,
    this.minimalFlagCalledEvents = false,
  });

  /// Derived flag values (key → `bool` | `String` variant) for convenience.
  Map<String, PostHogFeatureFlagValue> get featureFlags {
    final result = <String, PostHogFeatureFlagValue>{};
    for (final entry in flags.entries) {
      result[entry.key] = entry.value.variant ?? entry.value.enabled;
    }
    return result;
  }
}

/// Feature identifiers the server reports in
/// [PostHogFlagsResponse.quotaLimited].
abstract final class QuotaLimitedFeature {
  static const String featureFlags = 'feature_flags';
}

/// Error type for the `$feature_flag_error` analytics property.
enum FeatureFlagErrorType {
  errorsWhileComputing('errors_while_computing_flags'),
  flagMissing('flag_missing'),
  quotaLimited('quota_limited'),
  timeout('timeout'),
  connectionError('connection_error'),
  unknownError('unknown_error');

  final String value;
  const FeatureFlagErrorType(this.value);

  /// Returns an API error string with the given HTTP status code.
  static String apiError(int status) => 'api_error_$status';
}

/// Type of error that occurred during a feature flag request.
enum FeatureFlagRequestErrorType {
  timeout,
  connectionError,
  apiError,
  unknownError,
}

/// Represents an error that occurred during a feature flag request.
class FeatureFlagRequestError {
  final FeatureFlagRequestErrorType type;
  final int? statusCode;

  const FeatureFlagRequestError({required this.type, this.statusCode});

  Map<String, Object?> toJson() => {
        'type': type.name,
        if (statusCode != null) 'statusCode': statusCode,
      };

  factory FeatureFlagRequestError.fromJson(Map<String, Object?> json) {
    return FeatureFlagRequestError(
      type: FeatureFlagRequestErrorType.values
          .firstWhere((e) => e.name == json['type'] as String),
      statusCode: json['statusCode'] as int?,
    );
  }
}

/// Result type for flag fetching operations.
sealed class GetFlagsResult {}

class GetFlagsSuccess extends GetFlagsResult {
  final PostHogFlagsResponse response;
  GetFlagsSuccess(this.response);
}

class GetFlagsFailure extends GetFlagsResult {
  final FeatureFlagRequestError error;
  GetFlagsFailure(this.error);
}

/// Flags storage format for persistence.
class PostHogFlagsStorageFormat {
  final Map<String, PostHogFeatureFlagDetail> flags;
  final String? requestId;
  final int? evaluatedAt;
  final bool? errorsWhileComputingFlags;
  final List<String>? quotaLimited;
  final FeatureFlagRequestError? requestError;
  final bool? minimalFlagCalledEvents;

  const PostHogFlagsStorageFormat({
    required this.flags,
    this.requestId,
    this.evaluatedAt,
    this.errorsWhileComputingFlags,
    this.quotaLimited,
    this.requestError,
    this.minimalFlagCalledEvents,
  });

  /// The stored state viewed as a flags response ([requestError] is the
  /// only field without a response counterpart).
  PostHogFlagsResponse toResponse() => PostHogFlagsResponse(
        flags: flags,
        errorsWhileComputingFlags: errorsWhileComputingFlags ?? false,
        quotaLimited: quotaLimited,
        requestId: requestId,
        evaluatedAt: evaluatedAt,
        minimalFlagCalledEvents: minimalFlagCalledEvents ?? false,
      );

  Map<String, Object?> toJson() => {
        'flags': flags.map((k, v) => MapEntry(k, v.toJson())),
        if (requestId != null) 'requestId': requestId,
        if (evaluatedAt != null) 'evaluatedAt': evaluatedAt,
        if (errorsWhileComputingFlags != null)
          'errorsWhileComputingFlags': errorsWhileComputingFlags,
        if (quotaLimited != null) 'quotaLimited': quotaLimited,
        if (requestError != null) 'requestError': requestError!.toJson(),
        if (minimalFlagCalledEvents != null)
          'minimalFlagCalledEvents': minimalFlagCalledEvents,
      };

  factory PostHogFlagsStorageFormat.fromJson(
    Map<String, Object?> json, {
    required void Function(String key, Object error) onMalformedFlag,
  }) {
    final flagsRaw = json['flags'] as Map<String, Object?>? ?? {};
    return PostHogFlagsStorageFormat(
      flags: PostHogFeatureFlagDetail.parseAll(flagsRaw,
          onMalformed: onMalformedFlag),
      requestId: json['requestId'] as String?,
      evaluatedAt: json['evaluatedAt'] as int?,
      errorsWhileComputingFlags: json['errorsWhileComputingFlags'] as bool?,
      quotaLimited: (json['quotaLimited'] as List<Object?>?)
          ?.map((e) => e as String)
          .toList(),
      requestError: json['requestError'] != null
          ? FeatureFlagRequestError.fromJson(
              json['requestError'] as Map<String, Object?>)
          : null,
      minimalFlagCalledEvents: json['minimalFlagCalledEvents'] as bool?,
    );
  }
}
