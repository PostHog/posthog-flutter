import 'dart:async';

import 'posthog_event.dart';
import 'posthog_flutter_platform_interface.dart';

/// Callback to intercept and modify events before they are sent to PostHog.
///
/// Return a possibly modified event to send it, or return `null` to drop it.
/// Callbacks can be synchronous or asynchronous (returning `FutureOr<PostHogEvent?>`).
typedef BeforeSendCallback = FutureOr<PostHogEvent?> Function(
    PostHogEvent event);

/// Controls when person profiles are created in PostHog.
///
/// Person profiles allow you to associate events with specific users and
/// view their properties and event history in the PostHog UI.
enum PostHogPersonProfiles {
  /// Never create person profiles. All events are anonymous.
  never,

  /// Always create person profiles for every event.
  always,

  /// Only create person profiles when [Posthog.identify] is called.
  identifiedOnly,
}

/// Controls which network types are allowed for sending analytics data.
///
/// iOS only.
enum PostHogDataMode {
  /// Only send data over Wi-Fi connections.
  wifi,

  /// Only send data over cellular connections.
  cellular,

  /// Send data over any available network connection.
  any,
}

/// Configuration for the PostHog SDK.
///
/// Pass an instance of this class to [Posthog.setup] to initialize the SDK.
///
/// Only [apiKey] is required; all other properties have sensible defaults.
///
/// ```dart
/// final config = PostHogConfig('YOUR_API_KEY');
/// config.host = 'https://eu.i.posthog.com';
/// config.debug = true;
/// await Posthog().setup(config);
/// ```
class PostHogConfig {
  /// The project API key used to authenticate with your PostHog instance.
  final String apiKey;

  /// The URL of your PostHog instance.
  ///
  /// Defaults to `https://us.i.posthog.com`.
  var host = 'https://us.i.posthog.com';

  /// The number of queued events that triggers an automatic flush.
  ///
  /// Defaults to 20.
  var flushAt = 20;

  /// The maximum number of events to keep in the local queue.
  ///
  /// Events captured after the queue is full will be dropped.
  /// Defaults to 1000.
  var maxQueueSize = 1000;

  /// The maximum number of events sent in a single batch request.
  ///
  /// Defaults to 50.
  var maxBatchSize = 50;

  /// The interval at which queued events are automatically flushed.
  ///
  /// Defaults to 30 seconds.
  var flushInterval = const Duration(seconds: 30);

  /// Whether to automatically send a `$feature_flag_called` event when
  /// a feature flag is evaluated.
  ///
  /// Defaults to `true`.
  var sendFeatureFlagEvents = true;

  /// Whether to automatically load feature flags when the SDK is initialized.
  ///
  /// Defaults to `true`.
  var preloadFeatureFlags = true;

  /// Whether to automatically capture application lifecycle events such as
  /// `Application Opened`, `Application Backgrounded`, and `Application Installed`.
  ///
  /// Defaults to `false`.
  var captureApplicationLifecycleEvents = false;

  /// Whether to enable verbose debug logging for the SDK.
  ///
  /// Defaults to `false`.
  var debug = false;

  /// Whether the user has opted out of analytics tracking.
  ///
  /// When `true`, no events are captured. Defaults to `false`.
  var optOut = false;

  /// Controls when person profiles are created.
  ///
  /// Defaults to [PostHogPersonProfiles.identifiedOnly].
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
  /// **Example (async callback):**
  /// ```dart
  /// config.beforeSend = [
  ///   (event) async {
  ///     // Perform async operations
  ///     final shouldSend = await checkIfEventAllowed(event.event);
  ///     if (!shouldSend) {
  ///       return null; // Drop the event
  ///     }
  ///     // Enrich event with async data
  ///     final extraData = await fetchExtraContext();
  ///     event.properties = {...?event.properties, ...extraData};
  ///     return event;
  ///   },
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
  /// - Callbacks can be synchronous or asynchronous (via `FutureOr<PostHogEvent?>`)
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

/// Configuration options for session replay recording.
///
/// Adjust these settings to control what is captured and how often
/// snapshots are taken. Set via [PostHogConfig.sessionReplayConfig].
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

/// Configuration for automatic error and exception capture.
///
/// Controls which error sources are automatically captured and how
/// stack trace frames are classified. Set via [PostHogConfig.errorTrackingConfig].
class PostHogErrorTrackingConfig {
  /// List of package names to be considered inApp frames for exception tracking
  ///
  /// inApp Example:
  /// inAppIncludes.addAll(["package:your_app", "package:your_company_utils"])
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
  /// inAppExcludes.addAll(["package:third_party_lib", "package:analytics_package"])
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
  /// Default: false
  var captureFlutterErrors = false;

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
