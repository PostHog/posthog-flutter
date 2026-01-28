import 'posthog_event.dart';
import 'posthog_flutter_platform_interface.dart';

/// Callback to intercept and modify events before they are sent to PostHog.
///
/// Return a possibly modified event to send it, or return `null` to drop it.
typedef BeforeSendCallback = PostHogEvent? Function(PostHogEvent event);

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

  /// Enable Surveys
  ///
  /// **Notes:**
  /// - After calling `Posthog().close()`, surveys will not be rendered until the SDK is re-initialized and the next navigation event occurs.
  /// - You must install `PosthogObserver` in your app for surveys to display
  ///   - See: https://posthog.com/docs/surveys/installation?tab=Flutter#step-two-install-posthogobserver
  /// - For Flutter web, this setting will be ignored. Surveys on web use the JavaScript Web SDK instead.
  ///   - See: https://posthog.com/docs/surveys/installation?tab=Web
  ///
  /// Defaults to true.
  var surveys = true;

  /// Configuration for error tracking and exception capture
  final errorTrackingConfig = PostHogErrorTrackingConfig();

  /// Callback to be invoked when feature flags are loaded.
  ///
  /// Use [Posthog.getFeatureFlag] or [Posthog.isFeatureEnabled] within this
  /// callback to access the loaded flag values.
  OnFeatureFlagsCallback? onFeatureFlags;

  /// Callbacks to intercept and modify events before they are sent to PostHog.
  ///
  /// Callbacks are invoked in order for events captured via Dart APIs:
  /// - `Posthog().capture()` - custom events
  /// - `Posthog().screen()` - screen events (event name will be `$screen`)
  /// - `Posthog().captureException()` - exception events (event name will be `$exception`)
  ///
  /// Each callback receives the event (possibly modified by previous callbacks).
  /// Return a possibly modified event to continue, or return `null` to drop it.
  ///
  /// **Example (single callback):**
  /// ```dart
  /// config.beforeSend = [(event) {
  ///   // Drop specific events
  ///   if (event.event == 'sensitive_event') {
  ///     return null;
  ///   }
  ///   return event;
  /// }];
  /// ```
  ///
  /// **Example (multiple callbacks):**
  /// ```dart
  /// config.beforeSend = [
  ///   // First: PII redaction
  ///   (event) {
  ///     event.properties?.remove('email');
  ///     return event;
  ///   },
  ///   // Second: Event filtering
  ///   (event) => event.event == 'drop me' ? null : event,
  /// ];
  /// ```
  ///
  /// **Limitations:**
  /// - These callbacks do NOT intercept native-initiated events such as:
  ///   - Session replay events (`$snapshot`) when `config.sessionReplay` is enabled
  ///   - Application lifecycle events (`Application Opened`, etc.) when `config.captureApplicationLifecycleEvents` is enabled
  ///   - Feature flag events (`$feature_flag_called`) when `config.sendFeatureFlagEvents` is enabled
  ///   - Identity events (`$set`) when `identify` is called
  ///   - Survey events (`survey shown`, etc.) when `config.surveys` is enabled
  /// - Only user-provided properties are available; system properties
  ///   (like `$device_type`, `$session_id`) are added by the native SDK at a later stage.
  ///
  /// **Note:**
  /// - Callbacks run synchronously on the Dart side
  /// - Exceptions in a callback will skip that callback and continue with the next one in the list
  /// - If any callback returns `null`, the event is dropped and subsequent callbacks are not called.
  List<BeforeSendCallback> beforeSend = [];

  // TODO: missing getAnonymousId, propertiesSanitizer, captureDeepLinks integrations

  PostHogConfig(
    this.apiKey, {
    this.onFeatureFlags,
    List<BeforeSendCallback>? beforeSend,
  }) : beforeSend = beforeSend ?? [];

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
  /// **Note:**
  /// - Flutter web: Not supported
  ///
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
  /// **Note:**
  /// - Flutter web: Not supported
  ///
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
  /// **Note:**
  /// - Flutter web: Not supported
  ///
  var inAppByDefault = true;

  /// Enable automatic capture of Flutter framework errors
  ///
  /// Controls whether `FlutterError.onError` errors are captured.
  ///
  /// **Note:**
  /// - Flutter web: Not supported
  ///
  /// Default: false
  var captureFlutterErrors = false;

  /// Enable capturing of silent Flutter errors
  ///
  /// Controls whether Flutter errors marked as silent (FlutterErrorDetails.silent = true) are captured.
  ///
  /// **Note:**
  /// - Flutter web: Not supported
  ///
  /// Default: false
  var captureSilentFlutterErrors = false;

  /// Enable automatic capture of Dart runtime errors
  ///
  /// Controls whether `PlatformDispatcher.onError errors` are captured.
  ///
  /// **Note:**
  /// - Flutter web: Not supported
  ///
  /// Default: false
  var capturePlatformDispatcherErrors = false;

  /// Enable automatic capture of exceptions in the native SDKs (Android only for now)
  ///
  /// Controls whether native exceptions are captured.
  ///
  /// **Note:**
  /// - iOS: Not supported
  /// - Android: Java/Kotlin exceptions only (no native C/C++ crashes)
  /// - Android: No stacktrace demangling for minified builds
  ///
  /// Default: false
  var captureNativeExceptions = false;

  /// Enable automatic capture of isolate errors
  ///
  /// Controls whether errors from the current isolate are captured.
  /// This includes errors from the main isolate and any isolates spawned
  /// without explicit error handling.
  ///
  /// **Note:**
  /// - Flutter web: Not supported
  ///
  /// Default: false
  var captureIsolateErrors = false;

  Map<String, dynamic> toMap() {
    return {
      'inAppIncludes': inAppIncludes,
      'inAppExcludes': inAppExcludes,
      'inAppByDefault': inAppByDefault,
      'captureFlutterErrors': captureFlutterErrors,
      'captureSilentFlutterErrors': captureSilentFlutterErrors,
      'capturePlatformDispatcherErrors': capturePlatformDispatcherErrors,
      'captureNativeExceptions': captureNativeExceptions,
      'captureIsolateErrors': captureIsolateErrors,
    };
  }
}
