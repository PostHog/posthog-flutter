import 'dart:async';

import 'logs/posthog_log_record.dart';
import 'posthog_event.dart';
import 'posthog_flutter_platform_interface.dart';

/// Callback to intercept and modify events before they are sent to PostHog.
///
/// The [event] argument contains the event name and user-provided properties
/// that are about to be captured. Return a possibly modified event to send it,
/// or return `null` to drop it.
///
/// Callbacks can be synchronous or asynchronous (returning
/// `FutureOr<PostHogEvent?>`).
typedef BeforeSendCallback = FutureOr<PostHogEvent?> Function(
  PostHogEvent event,
);

/// Callback to intercept and modify log records before they are sent to
/// PostHog.
///
/// The [record] argument contains the body, level, and user-provided
/// attributes that are about to be captured. Return a possibly modified record
/// to send it, or return `null` to drop it.
///
/// Callbacks can be synchronous or asynchronous (returning
/// `FutureOr<PostHogLogRecord?>`).
typedef BeforeSendLogCallback = FutureOr<PostHogLogRecord?> Function(
  PostHogLogRecord record,
);

/// Controls whether events create or update PostHog person profiles.
enum PostHogPersonProfiles {
  /// Never create person profiles from captured events.
  never,

  /// Create or update person profiles for all captured events.
  always,

  /// Create or update person profiles only after the user has been identified.
  identifiedOnly,
}

/// Controls which network connection types can be used for sending data.
///
/// This setting is currently applied only on Apple platforms.
enum PostHogDataMode {
  /// Send data only on Wi-Fi connections.
  wifi,

  /// Send data only on cellular connections.
  cellular,

  /// Send data on any available connection.
  any,
}

/// Configuration used to initialize the PostHog Flutter SDK.
///
/// Create an instance with your project token, customize any options, and pass
/// it to `Posthog().setup(config)`.
class PostHogConfig {
  static const _defaultHost = 'https://us.i.posthog.com';

  /// Your PostHog project token.
  ///
  /// You can find it at:
  /// https://us.posthog.com/settings/project-details#variables
  ///
  /// This field was formerly named [apiKey].
  final String projectToken;

  /// Deprecated alias for [projectToken].
  @Deprecated(
    'Deprecated in favor of [projectToken]. This will be removed in the next major version.',
  )
  String get apiKey => projectToken;

  String _host = _defaultHost;

  /// The PostHog ingestion host.
  ///
  /// Defaults to `https://us.i.posthog.com`. The setter trims surrounding
  /// whitespace and falls back to the default host when assigned a blank value.
  String get host => _host;
  set host(String value) => _host = _normalizeHost(value);

  /// Number of queued events that triggers an automatic flush.
  ///
  /// Defaults to `20`.
  var flushAt = 20;

  /// Maximum number of events stored in the local queue.
  ///
  /// When the queue is full, the oldest events may be dropped by the native SDK.
  /// Defaults to `1000`.
  var maxQueueSize = 1000;

  /// Maximum number of events sent in a single batch.
  ///
  /// Defaults to `50`.
  var maxBatchSize = 50;

  /// Maximum time between automatic flush attempts.
  ///
  /// Defaults to 30 seconds.
  var flushInterval = const Duration(seconds: 30);

  /// Whether calls that evaluate feature flags capture `$feature_flag_called`.
  ///
  /// Defaults to `true`.
  var sendFeatureFlagEvents = true;

  /// Whether feature flags are loaded when the SDK starts.
  ///
  /// Defaults to `true`.
  var preloadFeatureFlags = true;

  /// Whether the SDK captures application lifecycle events automatically.
  ///
  /// Captured events include app opened, backgrounded, installed, and updated
  /// events where supported by the platform. Defaults to `true`.
  var captureApplicationLifecycleEvents = true;

  /// Whether the SDK emits verbose debug logs.
  ///
  /// Defaults to `false`.
  var debug = false;

  /// Whether the SDK starts with data collection disabled.
  ///
  /// Defaults to `false`. Use `Posthog().disable()` and `Posthog().enable()` to
  /// change this setting at runtime.
  var optOut = false;

  /// Controls whether captured events create or update person profiles.
  ///
  /// Defaults to [PostHogPersonProfiles.identifiedOnly].
  var personProfiles = PostHogPersonProfiles.identifiedOnly;

  /// Whether mobile session replay is enabled for Android and iOS.
  ///
  /// Requires Record user sessions to be enabled in PostHog project settings.
  /// Defaults to `false`.
  var sessionReplay = false;

  /// Configuration for mobile session replay.
  ///
  /// [sessionReplay] must be enabled for these options to take effect.
  var sessionReplayConfig = PostHogSessionReplayConfig();

  /// Network connection types that can be used to send data on Apple platforms.
  ///
  /// Defaults to [PostHogDataMode.any].
  var dataMode = PostHogDataMode.any;

  /// Enable Surveys
  ///
  /// **Notes:**
  /// - After calling `Posthog().close()`, surveys will not be rendered until the
  ///   SDK is re-initialized and the next navigation event occurs.
  /// - You must install `PosthogObserver` in your app for surveys to display.
  ///   - See: https://posthog.com/docs/surveys/installation?tab=Flutter#step-two-install-posthogobserver
  /// - For Flutter web, this setting will be ignored. Surveys on web use the
  ///   JavaScript Web SDK instead.
  ///   - See: https://posthog.com/docs/surveys/installation?tab=Web
  ///
  /// Defaults to true.
  var surveys = true;

  /// Configuration for error tracking and exception capture.
  final errorTrackingConfig = PostHogErrorTrackingConfig();

  /// Configuration for the logs subsystem (`Posthog().captureLog()` and the
  /// `Posthog().logger` facade).
  final logsConfig = PostHogLogsConfig();

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
  /// - `Posthog().captureException()` - exception events (event name will be
  ///   `$exception`)
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
  ///   - Session replay events (`$snapshot`) when `config.sessionReplay` is
  ///     enabled
  ///   - Application lifecycle events (`Application Opened`, etc.) when
  ///     `config.captureApplicationLifecycleEvents` is enabled
  ///   - Feature flag events (`$feature_flag_called`) when
  ///     `config.sendFeatureFlagEvents` is enabled
  ///   - Identity events (`$set`) when `identify` is called
  ///   - Survey events (`survey shown`, etc.) when `config.surveys` is enabled
  /// - Only user-provided properties are available; system properties (like
  ///   `$device_type`, `$session_id`) are added by the native SDK at a later
  ///   stage.
  ///
  /// **Note:**
  /// - Callbacks can be synchronous or asynchronous (via
  ///   `FutureOr<PostHogEvent?>`)
  /// - Exceptions in a callback will skip that callback and continue with the
  ///   next one in the list.
  /// - If any callback returns `null`, the event is dropped and subsequent
  ///   callbacks are not called.
  List<BeforeSendCallback> beforeSend = [];

  // TODO: missing getAnonymousId, propertiesSanitizer, captureDeepLinks integrations

  /// Creates a configuration for [projectToken].
  ///
  /// The [projectToken] is trimmed before it is stored.
  ///
  /// The optional [onFeatureFlags] callback is invoked when feature flags finish
  /// loading.
  ///
  /// The optional [beforeSend] callbacks are copied into [beforeSend] and run in
  /// order before Dart-captured events are sent.
  PostHogConfig(
    String projectToken, {
    this.onFeatureFlags,
    List<BeforeSendCallback>? beforeSend,
  })  : projectToken = projectToken.trim(),
        beforeSend = beforeSend ?? [];

  static String _normalizeHost(String host) {
    final trimmedHost = host.trim();
    return trimmedHost.isEmpty ? _defaultHost : trimmedHost;
  }

  /// Converts this configuration to a platform-channel map.
  ///
  /// Returns the values consumed by the Android, Apple, and web implementations.
  Map<String, dynamic> toMap() {
    return {
      'projectToken': projectToken,
      'apiKey': projectToken,
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
      'logs': logsConfig.toMap(),
    };
  }
}

/// Configuration for the logs subsystem.
///
/// Assign values before calling `Posthog().setup(config)`. The identity and
/// tuning fields are forwarded to the native iOS/Android logs configuration;
/// [beforeSend] runs in Dart before a record is forwarded to the native SDK.
///
/// Every field that is `null` (or, for [resourceAttributes], empty) is left at
/// the native SDK's default — it is not sent over the channel.
///
/// **Flutter web:** this configuration is **not** applied on web. The web SDK
/// hooks onto an already-initialized posthog-js instance, so configure logs in
/// your `posthog.init({...})` call instead. Only [beforeSend] runs on web (in
/// Dart).
class PostHogLogsConfig {
  /// Creates a logs configuration with native defaults.
  PostHogLogsConfig();

  /// Sets the OTLP `service.name` resource attribute.
  ///
  /// When `null`, the native SDK's default is used (the app bundle id on Apple
  /// platforms, the app namespace on Android).
  String? serviceName;

  /// Sets the OTLP `service.version` resource attribute.
  ///
  /// When `null`, the native SDK's default is used (the app version where the
  /// platform provides one).
  String? serviceVersion;

  /// Sets the OTLP `deployment.environment` resource attribute (e.g.
  /// `production`, `staging`). When `null`, the native SDK's default is used
  /// (no environment).
  String? environment;

  /// Extra OTLP resource attributes merged into every payload.
  ///
  /// SDK-managed identity keys (`service.*`, `telemetry.sdk.*`) take precedence
  /// and cannot be overridden.
  Map<String, Object> resourceAttributes = {};

  /// Periodic auto-flush interval. When `null`, the native default is used
  /// (30s on iOS/Android).
  Duration? flushInterval;

  /// Queue depth that triggers an immediate flush. When `null`, the native
  /// default is used (20 on iOS/Android).
  int? flushAt;

  /// Maximum number of records sent per POST. When `null`, the native default
  /// is used (50 on iOS/Android).
  int? maxBatchSize;

  /// Maximum number of buffered records before the oldest are dropped (FIFO).
  /// When `null`, the native default is used (1000 on iOS/Android).
  int? maxBufferSize;

  /// Maximum number of logs accepted per rate-cap window before excess logs are
  /// dropped. When `null`, the native default is used (500 on iOS/Android). A
  /// non-positive value disables the cap natively.
  int? rateCapMaxLogs;

  /// Length of the rate-cap window. When `null`, the native default is used
  /// (10s on iOS/Android).
  Duration? rateCapWindow;

  /// Callbacks to intercept and modify log records before they are forwarded to
  /// the native SDK.
  ///
  /// Callbacks are invoked in order for records captured via
  /// `Posthog().captureLog()` and the `Posthog().logger` facade. Each callback
  /// receives the record (possibly modified by previous callbacks). Return a
  /// possibly modified record to continue, or return `null` to drop it.
  /// Blanking the body also drops the record.
  ///
  /// **Example:**
  /// ```dart
  /// config.logsConfig.beforeSend = [
  ///   (record) {
  ///     record.attributes?.remove('password');
  ///     return record;
  ///   },
  ///   (record) => record.body.contains('secret') ? null : record,
  /// ];
  /// ```
  ///
  /// **Note:**
  /// - Runs in Dart on all platforms — it is intentionally not forwarded to the
  ///   native SDKs' own `beforeSend`. Dart callbacks cannot cross the platform
  ///   channel, and running it here gives identical behavior everywhere
  ///   (including web). This mirrors the event [PostHogConfig.beforeSend].
  /// - Callbacks can be synchronous or asynchronous (via
  ///   `FutureOr<PostHogLogRecord?>`).
  /// - A callback that throws is logged, and the record is dropped.
  /// - The W3C trace fields (`traceId`, `spanId`, `traceFlags`) are **not**
  ///   part of [PostHogLogRecord] and are not visible here. They pass straight
  ///   through to the native SDK, so they cannot be redacted or used to drop a
  ///   record. Keep anything sensitive out of those fields; put it in [body] or
  ///   [PostHogLogRecord.attributes], which a callback can scrub or drop.
  List<BeforeSendLogCallback> beforeSend = [];

  /// Converts the identity and tuning options to a platform-channel map.
  ///
  /// Only fields the user set are included, so unset fields keep the native
  /// default. [beforeSend] is intentionally omitted: it runs in Dart and never
  /// crosses the platform channel.
  Map<String, dynamic> toMap() {
    return {
      if (serviceName != null) 'serviceName': serviceName,
      if (serviceVersion != null) 'serviceVersion': serviceVersion,
      if (environment != null) 'environment': environment,
      if (resourceAttributes.isNotEmpty)
        'resourceAttributes': resourceAttributes,
      if (flushInterval != null)
        'flushIntervalSeconds': _wholeSeconds(flushInterval!),
      if (flushAt != null) 'flushAt': flushAt,
      if (maxBatchSize != null) 'maxBatchSize': maxBatchSize,
      if (maxBufferSize != null) 'maxBufferSize': maxBufferSize,
      if (rateCapMaxLogs != null) 'rateCapMaxLogs': rateCapMaxLogs,
      if (rateCapWindow != null)
        'rateCapWindowSeconds': _wholeSeconds(rateCapWindow!),
    };
  }

  /// The native flush interval and rate-cap window are whole seconds. A
  /// sub-second [Duration] truncates to `0`, which the native SDK treats as
  /// "disabled" (rate cap) or continuous flushing — surprising for a caller who
  /// set, say, 500ms. Floor at 1s, the smallest value the native API can honor.
  static int _wholeSeconds(Duration duration) =>
      duration.inSeconds < 1 ? 1 : duration.inSeconds;
}

/// Configuration for mobile session replay capture and masking.
///
/// Assign an instance to [PostHogConfig.sessionReplayConfig] before calling
/// `Posthog().setup(config)`.
class PostHogSessionReplayConfig {
  /// Creates a session replay configuration with default masking enabled.
  PostHogSessionReplayConfig();

  /// Enable masking of all text and text input fields.
  /// Default: true.
  var maskAllTexts = true;

  /// Enable masking of all images.
  /// Default: true.
  var maskAllImages = true;

  /// Deprecated setter that forwards assigned values to [throttleDelay].
  ///
  /// Debouncer delay used to reduce the number of snapshots captured and reduce
  /// performance impact. This is used for capturing the view as a screenshot.
  /// The lower the number, the more snapshots will be captured but higher the
  /// performance impact. Defaults to 1s.
  @Deprecated('Deprecated in favor of [throttleDelay] from v4.8.0.')
  set debouncerDelay(Duration debouncerDelay) {
    throttleDelay = debouncerDelay;
  }

  /// Throttling delay used to reduce the number of snapshots captured and reduce
  /// performance impact.
  ///
  /// This is used for capturing the view as a screenshot. The lower the number,
  /// the more snapshots will be captured but higher the performance impact.
  /// Defaults to 1s.
  var throttleDelay = const Duration(seconds: 1);

  /// Session replay sample rate between 0 and 1.
  /// Local config has precedence over remote config when both are set.
  /// If null, sampling is controlled by remote config (when available).
  double? sampleRate;

  /// Converts this session replay configuration to a platform-channel map.
  ///
  /// Returns values consumed by the Android and Apple session replay
  /// implementations.
  Map<String, dynamic> toMap() {
    return {
      'maskAllImages': maskAllImages,
      'maskAllTexts': maskAllTexts,
      'throttleDelayMs': throttleDelay.inMilliseconds,
      if (sampleRate != null) 'sampleRate': sampleRate,
    };
  }
}

/// Configuration for PostHog error tracking and exception capture.
class PostHogErrorTrackingConfig {
  /// Creates an error tracking configuration with all autocapture disabled.
  PostHogErrorTrackingConfig();

  /// List of package names to be considered in-app frames for exception tracking.
  ///
  /// Example:
  /// ```dart
  /// config.errorTrackingConfig.inAppIncludes.addAll([
  ///   'package:your_app',
  ///   'package:your_company_utils',
  /// ]);
  /// ```
  ///
  /// All exception stack trace frames from these packages will be considered
  /// in-app.
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

  /// List of package names to exclude from in-app frames for exception tracking.
  ///
  /// Example:
  /// ```dart
  /// config.errorTrackingConfig.inAppExcludes.addAll([
  ///   'package:third_party_lib',
  ///   'package:analytics_package',
  /// ]);
  /// ```
  ///
  /// All exception stack trace frames from these packages will be considered
  /// external.
  ///
  /// Note: [inAppIncludes] takes precedence over this setting.
  /// Common packages to exclude:
  /// - Third-party analytics packages
  /// - External utility libraries
  /// - Packages you don't control
  ///
  /// **Note:**
  /// - Flutter web: Not supported
  /// - Android: Not supported
  ///
  final inAppExcludes = <String>[];

  /// Configures whether stack trace frames are considered in-app by default
  /// when the origin cannot be determined or no explicit includes/excludes
  /// match.
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
  /// - Android: Not supported
  ///
  var inAppByDefault = true;

  /// Enable automatic capture of Flutter framework errors.
  ///
  /// Controls whether `FlutterError.onError` errors are captured.
  ///
  /// Default: false
  var captureFlutterErrors = false;

  /// Enable capturing of silent Flutter errors.
  ///
  /// Controls whether Flutter errors marked as silent
  /// (`FlutterErrorDetails.silent = true`) are captured.
  ///
  /// Default: false
  var captureSilentFlutterErrors = false;

  /// Enable automatic capture of Dart runtime errors.
  ///
  /// Controls whether `PlatformDispatcher.onError` errors are captured.
  ///
  /// **Note:**
  /// - Flutter web: Not supported
  ///
  /// Default: false
  var capturePlatformDispatcherErrors = false;

  /// Enable automatic capture of exceptions in the native SDKs
  /// (Android and Apple platforms).
  ///
  /// Controls whether native exceptions are captured.
  ///
  /// **Apple (iOS, macOS, tvOS):**
  ///
  /// Native error tracking on Apple platforms is currently experimental
  ///
  /// Captures Mach exceptions (e.g., EXC_BAD_ACCESS), POSIX signals
  /// (e.g., SIGSEGV, SIGABRT), and uncaught NSExceptions.
  /// Crashes are persisted to disk and sent as `$exception` events with
  /// level "fatal" on the next app launch.
  /// Not available on watchOS or visionOS due to platform limitations.
  ///
  /// For symbolicated stack traces, add a build phase script to your
  /// Xcode project to upload debug symbols.
  /// See: https://posthog.com/docs/error-tracking/upload-source-maps/ios
  ///
  /// **Android:**
  ///
  /// Captures Java/Kotlin exceptions only (no native C/C++ crashes).
  ///
  /// Stacktrace demangling for minified builds is supported by installing
  /// the PostHog Gradle plugin to upload ProGuard/R8 mappings.
  /// See: https://posthog.com/docs/error-tracking/upload-mappings/android
  ///
  /// Default: false
  var captureNativeExceptions = false;

  /// Enable automatic capture of isolate errors.
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

  /// Configuration for exception steps (breadcrumb-style context records
  /// attached to every captured `$exception` as `$exception_steps`).
  ///
  /// Record steps with `Posthog().addExceptionStep()`.
  final exceptionSteps = PostHogExceptionStepsConfig();

  /// Converts this error tracking configuration to a platform-channel map.
  ///
  /// Returns values consumed by the Android, Apple, and Dart exception capture
  /// implementations.
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
      'exceptionSteps': exceptionSteps.toMap(),
    };
  }
}

/// Configuration for exception steps.
///
/// Exception steps are breadcrumb-style context records recorded over time via
/// `Posthog().addExceptionStep()`. The SDK keeps a rolling, byte-bounded buffer
/// of these steps and attaches a snapshot to every captured `$exception` event
/// as `$exception_steps`, giving the error tracking UI a timeline of recent
/// activity leading up to each error.
///
/// The buffer is owned by the embedded native SDK (iOS/Android), so steps also
/// survive native fatal crashes and attach to the crash `$exception` reported
/// on the next launch.
///
/// **Flutter web:** the buffer lives in posthog-js. Steps are forwarded to it,
/// but they only attach to exceptions captured by posthog-js itself, not to
/// exceptions captured via `Posthog().captureException()` on web.
class PostHogExceptionStepsConfig {
  /// Creates an exception-steps configuration with native defaults.
  PostHogExceptionStepsConfig();

  /// Whether recording and attaching exception steps is enabled.
  ///
  /// When disabled, `Posthog().addExceptionStep()` is a no-op and nothing is
  /// attached. Defaults to `true`.
  var enabled = true;

  /// Total UTF-8 byte budget for the rolling step buffer.
  ///
  /// When adding a step would exceed the budget, the oldest steps are evicted
  /// until the total fits. A single step larger than the budget is rejected
  /// outright. Defaults to `32768` (32 KiB).
  var maxBytes = 32768;

  /// Converts this configuration to a platform-channel map.
  Map<String, Object> toMap() {
    return {
      'enabled': enabled,
      'maxBytes': maxBytes,
    };
  }
}
