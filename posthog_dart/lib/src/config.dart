import 'feature_flags.dart';

/// Function type for the `beforeSend` hook.
/// Receives an event and can return a modified event or null to drop the event.
/// Receives an event before it's queued. Return the (possibly modified) event,
/// or `null` to drop it.
typedef BeforeSendFn = CaptureEvent? Function(CaptureEvent event);

/// Configuration options for the PostHog SDK.
class PostHogCoreOptions {
  /// PostHog API host, usually 'https://us.i.posthog.com' or 'https://eu.i.posthog.com'.
  final String host;

  /// The number of events to queue before sending to PostHog (flushing).
  final int flushAt;

  /// The interval in milliseconds between periodic flushes.
  final int flushInterval;

  /// The maximum number of queued messages to be flushed as part of a single batch.
  final int maxBatchSize;

  /// The maximum number of cached messages either in memory or on the local storage.
  final int maxQueueSize;

  /// If set to true the SDK is essentially disabled.
  final bool disabled;

  /// If set to false the SDK will not track until the `optIn` function is called.
  final bool defaultOptIn;

  /// Whether to track that `getFeatureFlag` was called (used by Experiments).
  final bool sendFeatureFlagEvent;

  /// Whether to load feature flags when initialized or not.
  final bool preloadFeatureFlags;

  /// Option to bootstrap the library with given distinctId and feature flags.
  final BootstrapConfig? bootstrap;

  /// How many times we will retry HTTP requests.
  final int fetchRetryCount;

  /// The delay between HTTP request retries in milliseconds.
  final int fetchRetryDelay;

  /// Timeout in milliseconds for any calls.
  final int requestTimeout;

  /// Timeout in milliseconds for feature flag calls.
  final int? featureFlagsRequestTimeoutMs;

  /// Timeout in milliseconds for remote config calls.
  final int remoteConfigRequestTimeoutMs;

  /// For Session Analysis how long before we expire a session (in seconds).
  final int sessionExpirationTimeSeconds;

  /// Whether to disable GeoIP.
  final bool? disableGeoip;

  /// Evaluation contexts for feature flags.
  final List<String>? evaluationContexts;

  /// Determines when to create Person Profiles for users.
  final PersonProfiles personProfiles;

  /// Allows modification or dropping of events before they're sent to PostHog.
  final List<BeforeSendFn>? beforeSend;

  const PostHogCoreOptions({
    this.host = 'https://us.i.posthog.com',
    this.flushAt = 20,
    this.flushInterval = 10000,
    this.maxBatchSize = 100,
    this.maxQueueSize = 1000,
    this.disabled = false,
    this.defaultOptIn = true,
    this.sendFeatureFlagEvent = true,
    this.preloadFeatureFlags = true,
    this.bootstrap,
    this.fetchRetryCount = 3,
    this.fetchRetryDelay = 3000,
    this.requestTimeout = 10000,
    this.featureFlagsRequestTimeoutMs,
    this.remoteConfigRequestTimeoutMs = 3000,
    this.sessionExpirationTimeSeconds = 1800,
    this.disableGeoip,
    this.evaluationContexts,
    this.personProfiles = PersonProfiles.identifiedOnly,
    this.beforeSend,
  });

  /// Returns a copy with overridden defaults for the stateless base class.
  ///
  /// This is intentionally limited to the fields that [PostHogCore]
  /// needs to override when calling `super()`.
  PostHogCoreOptions withDefaults({
    bool? disableGeoip,
    int? featureFlagsRequestTimeoutMs,
  }) {
    return PostHogCoreOptions(
      host: host,
      flushAt: flushAt,
      flushInterval: flushInterval,
      maxBatchSize: maxBatchSize,
      maxQueueSize: maxQueueSize,
      disabled: disabled,
      defaultOptIn: defaultOptIn,
      sendFeatureFlagEvent: sendFeatureFlagEvent,
      preloadFeatureFlags: preloadFeatureFlags,
      bootstrap: bootstrap,
      fetchRetryCount: fetchRetryCount,
      fetchRetryDelay: fetchRetryDelay,
      requestTimeout: requestTimeout,
      featureFlagsRequestTimeoutMs:
          featureFlagsRequestTimeoutMs ?? this.featureFlagsRequestTimeoutMs,
      remoteConfigRequestTimeoutMs: remoteConfigRequestTimeoutMs,
      sessionExpirationTimeSeconds: sessionExpirationTimeSeconds,
      disableGeoip: disableGeoip ?? this.disableGeoip,
      evaluationContexts: evaluationContexts,
      personProfiles: personProfiles,
      beforeSend: beforeSend,
    );
  }
}

/// Determines when to create Person Profiles for users.
enum PersonProfiles {
  /// Always create a person profile for every user.
  always,

  /// Only create a person profile when the user is identified.
  identifiedOnly,

  /// Never create person profiles.
  never,
}

/// Bootstrap configuration.
class BootstrapConfig {
  final String? distinctId;
  final bool isIdentifiedId;

  /// Bootstrap feature flags as a map of flag key to [FeatureFlagDetail].
  final Map<String, FeatureFlagDetail>? flags;

  const BootstrapConfig({
    this.distinctId,
    this.isIdentifiedId = false,
    this.flags,
  });
}

/// Capture options for individual events.
class PostHogCaptureOptions {
  /// If provided overrides the auto-generated event ID.
  final String? uuid;

  /// If provided overrides the auto-generated timestamp.
  final DateTime? timestamp;

  /// Whether to disable GeoIP for this event.
  final bool? disableGeoip;

  const PostHogCaptureOptions({
    this.uuid,
    this.timestamp,
    this.disableGeoip,
  });
}

/// Represents an event before it's sent to PostHog.
///
/// Exposed to the [BeforeSendFn] hook for modification or filtering.
class CaptureEvent {
  String uuid;
  String event;
  Map<String, Object?>? properties;
  Map<String, Object?>? set;
  Map<String, Object?>? setOnce;
  DateTime? timestamp;

  CaptureEvent({
    required this.uuid,
    required this.event,
    this.properties,
    this.set,
    this.setOnce,
    this.timestamp,
  });
}

