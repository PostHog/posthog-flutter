import 'dart:async';

import 'feature_flags.dart';
import 'uuid.dart';

/// Callback to intercept and modify events before they are sent to PostHog.
///
/// Return a possibly modified event to send it, or return `null` to drop it.
/// Callbacks can be synchronous or asynchronous (returning `FutureOr<PostHogEvent?>`).
typedef BeforeSendCallback = FutureOr<PostHogEvent?> Function(
    PostHogEvent event);

/// Configuration options for the PostHog SDK.
class PostHogConfig {
  /// PostHog API host, usually 'https://us.i.posthog.com' or 'https://eu.i.posthog.com'.
  final String host;

  /// The number of events to queue before sending to PostHog (flushing).
  final int flushAt;

  /// The interval between periodic flushes.
  /// Defaults to 10 seconds.
  final Duration flushInterval;

  /// The maximum number of queued messages to be flushed as part of a single batch.
  final int maxBatchSize;

  /// The maximum number of cached messages either in memory or on the local storage.
  final int maxQueueSize;

  /// If set to true the SDK is essentially disabled (opted out).
  final bool optOut;

  /// Enable debug logging.
  /// When enabled, the SDK will log events and other debug information.
  final bool debug;

  /// Whether to track that `getFeatureFlag` was called (used by Experiments).
  final bool sendFeatureFlagEvents;

  /// Whether to load feature flags when initialized or not.
  final bool preloadFeatureFlags;

  /// Option to bootstrap the library with given distinctId and feature flags.
  final BootstrapConfig? bootstrap;

  /// How many times we will retry HTTP requests.
  final int fetchRetryCount;

  /// The delay between HTTP request retries.
  /// Defaults to 3 seconds.
  final Duration fetchRetryDelay;

  /// Timeout for any calls.
  /// Defaults to 10 seconds.
  final Duration requestTimeout;

  /// Timeout for feature flag calls.
  /// Defaults to 10 seconds.
  final Duration featureFlagsRequestTimeout;

  /// Timeout for remote config calls.
  /// Defaults to 3 seconds.
  final Duration remoteConfigRequestTimeout;

  /// For Session Analysis how long before we expire a session.
  /// Defaults to 30 minutes.
  final Duration sessionExpiration;

  /// Whether to disable GeoIP.
  /// Defaults to false.
  final bool disableGeoip;

  /// Evaluation contexts for feature flags.
  final List<String>? evaluationContexts;

  /// Determines when to create Person Profiles for users.
  final PostHogPersonProfiles personProfiles;

  /// Allows modification or dropping of events before they're sent to PostHog.
  final List<BeforeSendCallback>? beforeSend;

  const PostHogConfig({
    this.host = 'https://us.i.posthog.com',
    this.flushAt = 20,
    this.flushInterval = const Duration(seconds: 30),
    this.maxBatchSize = 50,
    this.maxQueueSize = 1000,
    this.optOut = false,
    this.debug = false,
    this.sendFeatureFlagEvents = true,
    this.preloadFeatureFlags = true,
    this.bootstrap,
    this.fetchRetryCount = 3,
    this.fetchRetryDelay = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 10),
    this.featureFlagsRequestTimeout = const Duration(seconds: 10),
    this.remoteConfigRequestTimeout = const Duration(seconds: 3),
    this.sessionExpiration = const Duration(minutes: 30),
    this.disableGeoip = false,
    this.evaluationContexts,
    this.personProfiles = PostHogPersonProfiles.identifiedOnly,
    this.beforeSend,
  });
}

/// Determines when to create Person Profiles for users.
enum PostHogPersonProfiles {
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
  /// The event ID.
  final String uuid;

  /// If provided overrides the auto-generated timestamp.
  final DateTime? timestamp;

  /// Whether to disable GeoIP for this event.
  final bool? disableGeoip;

  const PostHogCaptureOptions({
    required this.uuid,
    this.timestamp,
    this.disableGeoip,
  });
}

/// Represents an event before it's sent to PostHog.
///
/// Exposed to the [BeforeSendCallback] hook for modification or filtering.
class PostHogEvent {
  /// The event ID. Auto-generated as a UUIDv7 if not provided.
  String uuid;

  /// The name of the event (e.g., 'button_clicked', '$screen', '$exception').
  String event;

  /// User-provided properties for this event.
  Map<String, Object?>? properties;

  /// User properties to set on the user profile ($set).
  Map<String, Object?>? userProperties;

  /// User properties to set only once on the user profile ($set_once).
  Map<String, Object?>? userPropertiesSetOnce;

  /// If provided overrides the auto-generated timestamp.
  DateTime? timestamp;

  PostHogEvent({
    String? uuid,
    required this.event,
    this.properties,
    this.userProperties,
    this.userPropertiesSetOnce,
    this.timestamp,
  }) : uuid = uuid ?? generateUuidV7();

  @override
  String toString() {
    return 'PostHogEvent(event: $event, properties: $properties, userProperties: $userProperties, userPropertiesSetOnce: $userPropertiesSetOnce)';
  }
}
