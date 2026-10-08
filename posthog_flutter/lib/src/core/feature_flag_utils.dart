import 'feature_flags.dart';

/// Converts rich and legacy responses to [PostHogFlagsResponse].
PostHogFlagsResponse parseFlagsResponse(
  Map<String, Object?> response, {
  required void Function(String key, Object error) onMalformedFlag,
}) {
  final flags = response.containsKey('flags')
      ? PostHogFeatureFlagDetail.parseAll(
          response['flags'] as Map<String, Object?>? ?? {},
          onMalformed: onMalformedFlag,
        )
      : _parseLegacyFlags(response, onMalformedFlag: onMalformedFlag);

  return PostHogFlagsResponse(
    flags: flags,
    errorsWhileComputingFlags:
        response['errorsWhileComputingFlags'] as bool? ?? false,
    quotaLimited: (response['quotaLimited'] as List<Object?>?)
        ?.map((e) => e as String)
        .toList(),
    requestId: response['requestId'] as String?,
    evaluatedAt: response['evaluatedAt'] as int?,
    // Anything but an explicit true keeps full events.
    minimalFlagCalledEvents: response['minimalFlagCalledEvents'] == true,
  );
}

/// The v1 shape, without `flags`. PostHog answers `/flags/?v=2` with `flags`;
/// this keeps servers that ignore `v=2` working, as the other PostHog SDKs do.
Map<String, PostHogFeatureFlagDetail> _parseLegacyFlags(
  Map<String, Object?> response, {
  required void Function(String key, Object error) onMalformedFlag,
}) {
  final values = response['featureFlags'] as Map<String, Object?>? ?? {};
  final payloads = response['featureFlagPayloads'] as Map<String, Object?>?;
  final flags = <String, PostHogFeatureFlagDetail>{};
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is! bool && value is! String) {
      onMalformedFlag(entry.key,
          const FormatException('Feature flag value must be bool or String'));
      continue;
    }

    final rawPayload = payloads?[entry.key];
    if (rawPayload != null && rawPayload is! String) {
      onMalformedFlag(
          entry.key,
          const FormatException(
              'Feature flag payload must be serialized JSON'));
    }
    flags[entry.key] = PostHogFeatureFlagDetail(
      key: entry.key,
      enabled: value is String || value == true,
      variant: value is String ? value : null,
      metadata: rawPayload is String
          ? PostHogFeatureFlagMetadata(payload: rawPayload)
          : null,
    );
  }
  return flags;
}

/// Properties a minimal `$feature_flag_called` event keeps. The server asks
/// for minimal events per project, and they are only sent for flags that are
/// verifiably not linked to an experiment. Everything else - super
/// properties, `$feature/<key>`, `$active_feature_flags`, debug properties -
/// is dropped.
const minimalFeatureFlagCalledProperties = <String>{
  r'$feature_flag',
  r'$feature_flag_response',
  r'$feature_flag_has_experiment',
  r'$feature_flag_id',
  r'$feature_flag_version',
  r'$feature_flag_reason',
  r'$feature_flag_request_id',
  r'$feature_flag_evaluated_at',
  r'$feature_flag_error',
  r'$groups',
  r'$process_person_profile',
  r'$geoip_disable',
  r'$session_id',
  r'$window_id',
  r'$lib',
  r'$lib_version',
  r'$device_id',
  r'$os_name',
  r'$os_version',
  r'$app_version',
  // A minimal event can be the first event of a session, which is where the
  // server reads the session's campaign attribution from.
  r'$referring_domain',
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_content',
  'utm_term',
  'gad_source',
  'mc_cid',
  'gclid',
  'gclsrc',
  'dclid',
  'gbraid',
  'wbraid',
  'fbclid',
  'msclkid',
  'twclid',
  'li_fat_id',
  'igshid',
  'ttclid',
  'rdt_cid',
  'epik',
  'qclid',
  'sccid',
  'irclid',
  '_kx',
};

/// Get the value from a [PostHogFeatureFlagDetail].
///
/// Returns the variant string if present, the enabled bool otherwise.
/// Returns null if the detail is null.
PostHogFeatureFlagValue? getFeatureFlagValue(PostHogFeatureFlagDetail? detail) {
  if (detail == null) return null;
  return detail.variant ?? detail.enabled;
}
