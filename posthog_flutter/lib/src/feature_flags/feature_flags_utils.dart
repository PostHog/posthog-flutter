import 'dart:convert';

import 'feature_flags_types.dart';

/// Parses a JSON response body from the `/flags/?v=2` endpoint
/// into a [PostHogFlagsResponse].
GetFlagsResult parseFlagsResponse(String responseBody, int statusCode) {
  if (statusCode < 200 || statusCode >= 300) {
    return GetFlagsFailure(FeatureFlagRequestError(
      type: FeatureFlagRequestErrorType.httpError,
      message: 'HTTP $statusCode',
      statusCode: statusCode,
    ));
  }

  try {
    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    return GetFlagsSuccess(_parseResponseJson(json));
  } catch (e) {
    return GetFlagsFailure(FeatureFlagRequestError(
      type: FeatureFlagRequestErrorType.parseError,
      message: 'Failed to parse flags response: $e',
    ));
  }
}

PostHogFlagsResponse _parseResponseJson(Map<String, dynamic> json) {
  final flagsJson = json['flags'] as Map<String, dynamic>? ?? {};
  final flags = <String, FeatureFlagDetail>{};

  for (final entry in flagsJson.entries) {
    if (entry.value is Map) {
      flags[entry.key] = FeatureFlagDetail.fromJson(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
  }

  final quotaLimitedRaw = json['quotaLimited'] as List<dynamic>? ?? [];
  final quotaLimited =
      quotaLimitedRaw.whereType<String>().toList(growable: false);

  return PostHogFlagsResponse(
    flags: flags,
    errorsWhileComputingFlags:
        json['errorsWhileComputingFlags'] as bool? ?? false,
    quotaLimited: quotaLimited,
    requestId: json['requestId'] as String?,
    evaluatedAt: json['evaluatedAt'] as int?,
  );
}
