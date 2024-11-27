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
  var sessionReplay = false;

  var sessionReplayConfig = PostHogSessionReplayConfig();

  /// iOS only
  var dataMode = PostHogDataMode.any;

  // TODO: missing getAnonymousId, propertiesSanitizer, captureDeepLinks
  // onFeatureFlags, integrations

  PostHogConfig(this.apiKey);

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
  /// Enable masking of all text input fields
  /// Experimental support
  /// Default: true
  var maskAllTexts = true;

  /// Enable masking of all images to a placeholder
  /// Experimental support
  /// Default: true
  var maskAllImages = true;

  /// Debouncer delay used to reduce the number of snapshots captured and reduce performance impact
  /// This is used for capturing the view as a screenshot
  /// The lower the number, the more snapshots will be captured but higher the performance impact
  /// Defaults to 1s
  var debouncerDelay = const Duration(seconds: 1);

  Map<String, dynamic> toMap() {
    return {
      'maskAllImages': maskAllImages,
      'maskAllTexts': maskAllTexts,
      'debouncerDelayMs': debouncerDelay.inMilliseconds,
    };
  }
}
