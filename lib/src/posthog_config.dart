import 'package:meta/meta.dart';

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

  /// Enable Surveys (Currently for iOS only)
  ///
  /// Note: Please note that after calling Posthog().close(), surveys will not be rendered until the SDK is re-initialized and the next navigation event occurs.
  ///
  /// Experimental. Defaults to false.
  @experimental
  var surveys = false;

  /// Configuration for error tracking and exception capture
  final errorTrackingConfig = PostHogErrorTrackingConfig();

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
      'surveys': surveys,
      'personProfiles': personProfiles.name,
      'sessionReplay': sessionReplay,
      'dataMode': dataMode.name,
      'sessionReplayConfig': sessionReplayConfig.toMap(),
      'errorTrackingConfig': errorTrackingConfig.toMap(),
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

class PostHogErrorTrackingConfig {
  /// List of package names to be considered inApp frames for exception tracking
  ///
  /// inApp Example:
  /// inAppIncludes = ["package:your_app", "package:your_company_utils"]
  /// All exception stacktrace frames from these packages will be considered inApp
  ///
  /// This option takes precedence over inAppExcludes.
  /// For Flutter/Dart, this typically includes:
  /// - Your app's main package (e.g., "package:your_app")
  /// - Any internal packages you own (e.g., "package:your_company_utils")
  ///
  /// Note: This config will be ignored on web builds
  final inAppIncludes = <String>[];

  /// List of package names to be excluded from inApp frames for exception tracking
  ///
  /// inAppExcludes Example:
  /// inAppExcludes = ["package:third_party_lib", "package:analytics_package"]
  /// All exception stacktrace frames from these packages will be considered external
  ///
  /// Note: inAppIncludes takes precedence over this setting.
  /// Common packages to exclude:
  /// - Third-party analytics packages
  /// - External utility libraries
  /// - Packages you don't control
  ///
  /// Note: This config will be ignored on web builds
  final inAppExcludes = <String>[];

  /// Configures whether stack trace frames are considered inApp by default
  /// when the origin cannot be determined or no explicit includes/excludes match.
  ///
  /// - If true: Frames are inApp unless explicitly excluded (allowlist approach)
  /// - If false: Frames are external unless explicitly included (denylist approach)
  ///
  /// Default behavior when true:
  /// - Local files (no package prefix) are inApp
  /// - dart and flutter packages are excluded
  /// - All other packages are inApp unless in inAppExcludes
  ///
  /// Note: This config will be ignored on web builds
  var inAppByDefault = true;

  /// Enable automatic capture of Flutter framework errors
  ///
  /// Controls whether `FlutterError.onError` errors are captured.
  ///
  /// Default: true (when autocapture is enabled)
  var captureFlutterErrors = true;

  /// Enable capturing of silent Flutter errors
  ///
  /// Controls whether Flutter errors marked as silent (FlutterErrorDetails.silent = true) are captured.
  ///
  /// Default: false
  var captureSilentFlutterErrors = false;

  /// Enable automatic capture of Dart runtime errors
  ///
  /// Controls whether `PlatformDispatcher.onError errors` are captured.
  ///
  /// Default: true
  var capturePlatformDispatcherErrors = true;

  /// Enable automatic capture of exceptions in the native SDKs (Android only for now)
  ///
  /// Controls whether native exceptions are captured.
  ///
  /// Default: true
  var captureNativeExceptions = true;

  Map<String, dynamic> toMap() {
    return {
      'inAppIncludes': inAppIncludes,
      'inAppExcludes': inAppExcludes,
      'inAppByDefault': inAppByDefault,
      'captureFlutterErrors': captureFlutterErrors,
      'captureSilentFlutterErrors': captureSilentFlutterErrors,
      'capturePlatformDispatcherErrors': capturePlatformDispatcherErrors,
      'captureNativeExceptions': captureNativeExceptions,
    };
  }
}
