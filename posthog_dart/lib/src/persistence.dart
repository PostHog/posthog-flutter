/// Keys for persisted properties.
enum PostHogPersistedProperty {
  anonymousId('anonymous_id'),
  distinctId('distinct_id'),
  props('props'),
  enablePersonProcessing('enable_person_processing'),
  personMode('person_mode'),
  featureFlagDetails('feature_flag_details'),
  bootstrapFeatureFlagDetails('bootstrap_feature_flag_details'),
  overrideFeatureFlags('override_feature_flags'),
  queue('queue'),
  optedOut('opted_out'),
  sessionId('session_id'),
  sessionStartTimestamp('session_start_timestamp'),
  sessionLastTimestamp('session_timestamp'),
  personProperties('person_properties'),
  groupProperties('group_properties'),
  remoteConfig('remote_config'),
  flagsEndpointWasHit('flags_endpoint_was_hit');

  final String key;
  const PostHogPersistedProperty(this.key);
}
