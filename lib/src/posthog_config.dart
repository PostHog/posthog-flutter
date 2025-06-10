import 'posthog_flutter_platform_interface.dart';

enum PostHogPersonProfiles { never, always, identifiedOnly }

enum PostHogDataMode { wifi, cellular, any }

class PostHogConfig {
  final String apiKey;
  var host = 'https://us.i.posthog.com';
  var flushAt = 20;
  var maxQueueSize = 1000;
  var maxBatchSize = 50;
  var flushInterval = const Duration(seconds: 30);
  var sendFeatureFlagEvents = true;
  var preloadFeatureFlags = true;
  var captureApplicationLifecycleEvents = false;
  var debug = false;
  var optOut = false;
  var personProfiles = PostHogPersonProfiles.identifiedOnly;

  /// Enable Recording of Session replay for Android and iOS.
  /// Requires Record user sessions to be enabled in the PostHog Project Settings.
  /// Defaults to false.
  var sessionReplay = false;

  /// Configurations for Session replay.
  /// [sessionReplay] has to be enabled for this to take effect.
  var sessionReplayConfig = PostHogSessionReplayConfig();

  /// iOS only
  var dataMode = PostHogDataMode.any;

  /// Callback to be invoked when feature flags are loaded.
  /// See [Posthog.onFeatureFlags] for more details on behavior per platform.
  final OnFeatureFlagsCallback? onFeatureFlags;

  // TODO: missing getAnonymousId, propertiesSanitizer, captureDeepLinks
  // onFeatureFlags, integrations

  PostHogConfig(
    this.apiKey, {
    this.onFeatureFlags,
  });

  Map<String, dynamic> toMap() {
    return {
      'apiKey': apiKey,
      'host': host,
      'flushAt': flushAt,
      'maxQueueSize': maxQueueSize,
      'maxBatchSize': maxBatchSize,
      'flushInterval': flushInterval.inSeconds,
      'sendFeatureFlagEvents': sendFeatureFlagEvents,
      'preloadFeatureFlags': preloadFeatureFlags,
      'captureApplicationLifecycleEvents': captureApplicationLifecycleEvents,
      'debug': debug,
      'optOut': optOut,
      'personProfiles': personProfiles.name,
      'sessionReplay': sessionReplay,
      'dataMode': dataMode.name,
      'sessionReplayConfig': sessionReplayConfig.toMap(),
    };
  }
}

class PostHogSessionReplayConfig {
  /// Enable masking of all text and text input fields.
  /// Default: true.
  var maskAllTexts = true;

  /// Enable masking of all images.
  /// Default: true.
  var maskAllImages = true;

  /// The value assigned to this var will be forwarded to [throttleDelay]
  ///
  /// Debouncer delay used to reduce the number of snapshots captured and reduce performance impact.
  /// This is used for capturing the view as a screenshot.
  /// The lower the number, the more snapshots will be captured but higher the performance impact.
  /// Defaults to 1s.
  @Deprecated('Deprecated in favor of [throttleDelay] from v4.8.0.')
  set debouncerDelay(Duration debouncerDelay) {
    throttleDelay = debouncerDelay;
  }

  /// Throttling delay used to reduce the number of snapshots captured and reduce performance impact.
  /// This is used for capturing the view as a screenshot.
  /// The lower the number, the more snapshots will be captured but higher the performance impact.
  /// Defaults to 1s.
  var throttleDelay = const Duration(seconds: 1);

  Map<String, dynamic> toMap() {
    return {
      'maskAllImages': maskAllImages,
      'maskAllTexts': maskAllTexts,
      'throttleDelayMs': throttleDelay.inMilliseconds,
    };
  }
}
