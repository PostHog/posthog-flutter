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

  /// iOS only
  var dataMode = PostHogDataMode.any;

  // TODO: missing getAnonymousId, propertiesSanitizer, sessionReplay, captureDeepLinks
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
      'dataMode': dataMode.name,
    };
  }
}
