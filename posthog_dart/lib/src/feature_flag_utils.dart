import 'dart:convert';

import 'feature_flags.dart';

/// Parses a v2 flags response JSON into a [PostHogFlagsResponse].
PostHogFlagsResponse parseFlagsResponse(Map<String, Object?> response) {
  final flagsRaw = response['flags'] as Map<String, Object?>? ?? {};
  final flags = flagsRaw.map(
    (k, v) => MapEntry(
        k, FeatureFlagDetail.fromJson(v as Map<String, Object?>)),
  );

  return PostHogFlagsResponse(
    flags: flags,
    errorsWhileComputingFlags:
        response['errorsWhileComputingFlags'] as bool? ?? false,
    quotaLimited: (response['quotaLimited'] as List<Object?>?)
        ?.map((e) => e as String)
        .toList(),
    requestId: response['requestId'] as String?,
    evaluatedAt: response['evaluatedAt'] as int?,
  );
}

/// Get the value from a [FeatureFlagDetail].
///
/// Returns the variant string if present, the enabled bool otherwise.
/// Returns null if the detail is null.
FeatureFlagValue? getFeatureFlagValue(FeatureFlagDetail? detail) {
  if (detail == null) return null;
  return detail.variant ?? detail.enabled;
}

/// Parse a payload value, attempting JSON decode if it's a string.
Object? parsePayload(Object? response) {
  if (response is! String) return response;
  try {
    return jsonDecode(response);
  } catch (_) {
    return response;
  }
}

/// Update a flag detail with a new value.
FeatureFlagDetail updateFlagValue(
    FeatureFlagDetail? flag, FeatureFlagValue value) {
  return FeatureFlagDetail(
    key: flag?.key ?? '',
    enabled: value is String ? true : value as bool,
    variant: value is String ? value : null,
    reason: flag?.reason,
    metadata: flag?.metadata,
    failed: flag?.failed,
  );
}
