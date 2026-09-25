import 'dart:async';

import 'package:meta/meta.dart';

import 'logs/posthog_log_record.dart';
import 'posthog.dart';
import 'posthog_event.dart';
import 'posthog_flutter_platform_interface.dart';
import 'replay/mask/posthog_text_mask.dart';
import 'util/logging.dart';

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

/// Mints a signed identity-verification token for a push subscription request.
///
/// Called by the native SDK with the current [distinctId] and [appId]. Return
/// `null` to send the request without an identity token.
typedef PushIdentityProvider = Future<String?> Function(
  String distinctId,
  String appId,
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

/// Controls how the SDK compresses request bodies before sending them to the
/// PostHog API.
enum PostHogCompression {
  /// Gzip request bodies.
  gzip,

  /// Send request bodies uncompressed.
  none,
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
  /// Defaults to `true`, which means every SDK start issues a `/flags` request.
  /// Set it to `false` if you evaluate flags lazily (via
  /// `Posthog().reloadFeatureFlags()`) and want to avoid that request.
  ///
  /// Note that `Posthog().identify()`, `Posthog().group()` and the
  /// `set*PropertiesForFlags` helpers reload feature flags as well, so turning
  /// preloading off only removes the request made at startup.
  ///
  /// **Flutter web:** not applied. The web SDK hooks onto an already-initialized
  /// posthog-js instance, so set
  /// [`advanced_disable_feature_flags_on_first_load`](https://posthog.com/docs/libraries/js/config)
  /// in your `posthog.init({...})` call instead.
  var preloadFeatureFlags = true;

  /// Whether the SDK captures application lifecycle events automatically.
  ///
  /// Captured events include app opened, backgrounded, installed, and updated
  /// events where supported by the platform. Defaults to `true`.
  var captureApplicationLifecycleEvents = true;

  /// Configuration for rage-click autocapture on iOS and Mac Catalyst.
  ///
  /// Rage-click autocapture is not currently supported on other platforms.
  var rageClickConfig = PostHogRageClickConfig();

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

  /// Controls how request bodies are compressed before being sent to PostHog.
  ///
  /// Set this to [PostHogCompression.none] when something between the app and
  /// PostHog, e.g. a managed network or work profile, alters the gzip body.
  ///
  /// Defaults to [PostHogCompression.gzip].
  var compression = PostHogCompression.gzip;

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

  /// Pre-seeded identity and feature-flag state applied on the very first SDK
  /// launch, before any network request completes.
  ///
  /// Set this before calling `Posthog().setup(config)` so events captured during
  /// cold start carry a caller-controlled `$distinct_id` and feature-flag reads
  /// return caller-provided values before the first `/flags` response. Mirrors
  /// the [`bootstrap` option in `posthog-js`](https://posthog.com/docs/feature-flags/bootstrapping).
  ///
  /// Forwarded to the native iOS/Android SDKs, which apply all precedence rules
  /// (never overwrite persisted identity, overlay loaded flags over bootstrapped
  /// ones, drop the bootstrap on `reset()`). Defaults to `null` (no bootstrap).
  ///
  /// **Flutter web:** not applied. The web SDK hooks onto an already-initialized
  /// posthog-js instance, so configure `bootstrap` in your `posthog.init({...})`
  /// call instead.
  PostHogBootstrapConfig? bootstrap;

  /// Callback to be invoked when feature flags are loaded.
  ///
  /// Use [Posthog.getFeatureFlag] or [Posthog.isFeatureEnabled] within this
  /// callback to access the loaded flag values.
  OnFeatureFlagsCallback? onFeatureFlags;

  /// Whether to automatically register this device's push token with PostHog.
  ///
  /// On iOS the native SDK swizzles the app delegate's remote-notification
  /// registration callback; on Android it fetches the FCM token at startup when
  /// `firebase-messaging` is on the classpath. Either way the host app is still
  /// responsible for requesting notification permission and calling
  /// `registerForRemoteNotifications()` (iOS) — this only observes the result.
  ///
  /// The startup fetch does not see later token refreshes; wire those to
  /// [Posthog.registerPushNotificationToken] yourself.
  ///
  /// **Flutter web:** not supported. Defaults to `true`.
  bool capturePushNotificationSubscriptions = true;

  /// Whether to automatically capture `$push_notification_opened` when a user
  /// taps a PostHog-delivered notification.
  ///
  /// Every tap on a **remote** notification is captured on both platforms,
  /// whether it cold-launched the app or the app was already running.
  /// Locally-scheduled notifications are ignored. On Android a tap is
  /// recognised by the `google.message_id` extra Firebase puts on the intent,
  /// so push delivered outside FCM is not seen. Call
  /// [Posthog.capturePushNotificationOpened] for the opens this misses.
  ///
  /// **Flutter web:** not supported. Defaults to `true`.
  ///
  /// On iOS this requires your app to set `UNUserNotificationCenter.current().delegate`.
  /// Without one, iOS reports the tap to nobody and no open can be captured.
  ///
  /// Setting this to `false` does not prevent the iOS cold-start prewarm, which runs before
  /// Dart does — opt that out with the `com.posthog.posthog.CAPTURE_PUSH_NOTIFICATION_OPENED`
  /// key in `Info.plist`.
  bool capturePushNotificationOpened = true;

  /// Mints a signed identity-verification token for push subscription requests.
  ///
  /// Only needed when your PostHog project requires identity verification for
  /// push. The native SDK calls this with the current `distinctId` and `appId`
  /// and attaches the returned token to the subscription request; return `null`
  /// to send without one.
  ///
  /// The token is minted by your backend (HS256, with `sub` = distinctId,
  /// `app_id`, and `aud` = `posthog:push_identity`), never in the app.
  ///
  /// The native SDKs cache the result per `(distinctId, appId)` and give this
  /// callback 10 seconds before falling back to an unauthenticated request, so
  /// a slow or throwing implementation degrades rather than blocking delivery.
  ///
  /// Requires programmatic setup on both platforms. Under auto-init
  /// (`com.posthog.posthog.AUTO_INIT`, Info.plist on iOS, AndroidManifest
  /// `<meta-data>` on Android) the native SDK is already set up before Dart
  /// runs and a later [Posthog.setup] is a no-op, so the provider is never
  /// installed. Set `com.posthog.posthog.AUTO_INIT` to `false` and call
  /// [Posthog.setup].
  ///
  /// **Flutter web:** not supported. Defaults to `null`.
  PushIdentityProvider? pushIdentityProvider;

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

  // TODO: missing getAnonymousId, captureDeepLinks integrations

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
      'rageClickConfig': rageClickConfig.toMap(),
      'debug': debug,
      'optOut': optOut,
      'surveys': surveys,
      'personProfiles': personProfiles.name,
      'compression': compression.name,
      'sessionReplay': sessionReplay,
      'dataMode': dataMode.name,
      'sessionReplayConfig': sessionReplayConfig.toMap(),
      'errorTrackingConfig': errorTrackingConfig.toMap(),
      'logs': logsConfig.toMap(),
      'capturePushNotificationSubscriptions':
          capturePushNotificationSubscriptions,
      'capturePushNotificationOpened': capturePushNotificationOpened,
      // A closure can't cross the channel. This tells native whether to install
      // a bridging provider at all — installing one the host didn't ask for
      // would change how the native SDK handles a 401 on the subscription call.
      'pushIdentityProviderEnabled': pushIdentityProvider != null,
      if (bootstrap != null) 'bootstrap': bootstrap!.toMap(),
    };
  }
}

/// Pre-seeded identity and feature-flag state applied on the very first SDK
/// launch, before any network request completes.
///
/// Assign an instance to [PostHogConfig.bootstrap] before calling
/// `Posthog().setup(config)`. The values are forwarded to the native iOS/Android
/// SDKs, which own all bootstrap behavior:
///
/// - Bootstrapped identity seeds the very first session only. It is applied only
///   when no identity is persisted for that scope, and never overwrites an
///   existing user. An anonymous bootstrap ([isIdentifiedId] `false`) seeds the
///   anonymous id; an identified bootstrap ([isIdentifiedId] `true`) seeds the
///   distinct id and marks the user identified (merging an existing anonymous
///   user via `identify()`, or preserving a different identified user with a
///   warning) — it never becomes the device id.
/// - Only enabled bootstrapped flags are served (a `true` or a non-empty
///   variant string; `false` or empty values are dropped). They are served
///   until the first `/flags` response, which then takes over, and they are
///   dropped on `reset()`.
///
/// **Flutter web:** not applied. Configure `bootstrap` in your
/// `posthog.init({...})` call instead.
class PostHogBootstrapConfig {
  /// Creates a bootstrap configuration.
  ///
  /// Pass only the dimensions you want to seed; leave the rest `null`.
  const PostHogBootstrapConfig({
    this.distinctId,
    this.isIdentifiedId = false,
    this.featureFlags,
    this.featureFlagPayloads,
  });

  /// The distinct id to seed on first launch.
  ///
  /// When [isIdentifiedId] is `false` (the default) this becomes the anonymous
  /// id — the `$distinct_id` on pre-identify events. When `true` it is treated
  /// as an already-identified user's distinct id.
  final String? distinctId;

  /// Whether [distinctId] represents an already-identified user.
  ///
  /// Defaults to `false`. Set to `true` when the host application resolved the
  /// user's identity outside the SDK (for example from a backend session token).
  final bool isIdentifiedId;

  /// Feature flag values served until the first `/flags` response arrives,
  /// keyed by flag key. Each value is a `bool` for boolean flags or a `String`
  /// for multivariate flags. Only enabled values are served: `false` or an
  /// empty string is dropped.
  final Map<String, Object>? featureFlags;

  /// JSON payloads paired with [featureFlags], keyed by flag key. Each value is
  /// the already-decoded payload (map, list, string, number, `null`, ...).
  final Map<String, Object?>? featureFlagPayloads;

  /// Converts this configuration to a platform-channel map.
  ///
  /// Only the dimensions that were set are included; [isIdentifiedId] is always
  /// sent so the native SDK doesn't have to infer it.
  Map<String, Object?> toMap() {
    final flags = featureFlags;
    if (flags != null) {
      for (final entry in flags.entries) {
        // Only bool/String are served (see [featureFlags]); the native SDKs drop
        // anything else silently, so warn instead of leaving no trace.
        if (entry.value is! bool && entry.value is! String) {
          printIfDebug(
            '[PostHog] bootstrap featureFlags["${entry.key}"] is '
            '${entry.value.runtimeType}; only bool and String values are served, '
            'so this entry will be ignored.',
          );
        }
      }
    }
    return {
      if (distinctId != null) 'distinctId': distinctId,
      'isIdentifiedId': isIdentifiedId,
      if (featureFlags != null) 'featureFlags': featureFlags,
      if (featureFlagPayloads != null)
        'featureFlagPayloads': featureFlagPayloads,
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

/// Configuration for rage-click autocapture on iOS and Mac Catalyst.
///
/// Assign an instance to [PostHogConfig.rageClickConfig] before calling
/// `Posthog().setup(config)`. Other platforms ignore this configuration.
class PostHogRageClickConfig {
  /// Creates a rage-click configuration using the native defaults.
  PostHogRageClickConfig();

  /// Whether rapid repeated taps are captured as `$rageclick` events.
  ///
  /// Defaults to `true`.
  var enabled = true;

  /// Maximum Manhattan distance, in logical points, between consecutive taps.
  ///
  /// Defaults to `30`.
  var thresholdPoints = 30.0;

  /// Maximum time between consecutive taps in the same sequence.
  ///
  /// Defaults to one second.
  var timeoutInterval = const Duration(seconds: 1);

  /// Number of consecutive taps required to capture a rage click.
  ///
  /// Defaults to `3`.
  var minimumTapCount = 3;

  /// Converts this rage-click configuration to a platform-channel map.
  Map<String, Object> toMap() {
    return {
      'enabled': enabled,
      'thresholdPoints': thresholdPoints,
      'timeoutInterval':
          timeoutInterval.inMicroseconds / Duration.microsecondsPerSecond,
      'minimumTapCount': minimumTapCount,
    };
  }
}

/// Pixel format for Android native-screen captures in session replay.
@experimental
enum PostHogScreenshotColorMode {
  /// Preserve alpha and eight-bit color channels before compression.
  argb8888,

  /// Use half the bitmap memory with reduced color precision and no alpha.
  ///
  /// Transparent native window regions appear black. Devices that reject
  /// this format fall back to [argb8888].
  rgb565,
}

/// Configuration for mobile session replay capture and masking.
///
/// Assign an instance to [PostHogConfig.sessionReplayConfig] before calling
/// `Posthog().setup(config)`.
class PostHogSessionReplayConfig {
  /// Creates a session replay configuration with default masking enabled.
  PostHogSessionReplayConfig();

  /// Capture touch coordinates in session replay on Android and iOS.
  ///
  /// Masking screenshots does not hide touches on a known keypad layout.
  /// Set this before [Posthog.setup]. Runtime changes are not supported.
  /// Disabling touches does not stop screenshot capture.
  ///
  /// Default: true. Not supported on web or desktop.
  var captureTouches = true;

  /// Enable masking of all text and text input fields.
  /// Default: true. Wrap known-safe Flutter content in `PostHogUnmaskWidget`
  /// to reveal it without disabling masking globally.
  ///
  /// Sensitive Flutter inputs stay masked regardless of this flag, explicit
  /// masks, or unmask widgets. This includes `obscureText`, password, email,
  /// phone, name, address and URL keyboard types, and standard Flutter autofill
  /// hints for identity, contact, address, authentication, and payment data.
  /// Inputs without these signals are not automatically classified as
  /// sensitive. Annotate them appropriately or keep global masking enabled.
  /// `PostHogUnmaskWidget` overrides global and explicit masks for other content.
  ///
  /// Flutter web requires canvas masking to be enabled by mounting a
  /// `PostHogMaskWidget` or `PostHogUnmaskWidget` inside `PostHogWidget`, or by
  /// declaring `session_recording.canvasCapture.maskRegionsFn` in `posthog.init`.
  /// Declare it as `() => null` to skip frames before Flutter installs its mask
  /// provider. Canvas recording must be enabled separately.
  ///
  /// Does not mask text drawn by CustomPainter. Enable [maskCustomPaint] or
  /// wrap sensitive custom-painted widgets in PostHogMaskWidget to mask them.
  ///
  /// With [captureNativeScreens] enabled, setting this false also unmasks text
  /// on captured native screens, including native input fields (passwords,
  /// card numbers) you may not have built.
  var maskAllTexts = true;

  /// Enable masking of all images.
  /// Default: true. `PostHogUnmaskWidget` can reveal known-safe Flutter images;
  /// it overrides explicit masks within the same subtree too. Flutter web
  /// requires canvas masking to be enabled as described in [maskAllTexts].
  ///
  /// Does not mask images drawn by CustomPainter. Enable [maskCustomPaint] or
  /// wrap sensitive custom-painted widgets in PostHogMaskWidget to mask them.
  var maskAllImages = true;

  /// Mask the full bounds of CustomPaint widgets with a painter or
  /// foregroundPainter, including their children.
  /// Default: false.
  ///
  /// This is independent of [maskAllTexts] and [maskAllImages]. Canvas contents
  /// cannot be inspected for individual text or images, so enabling this also
  /// masks custom-painted decorations in Flutter widgets, including TabBar,
  /// checkboxes, switches, and progress indicators. Framework scrollbar-only
  /// painters are excluded, but their children are still checked for masks.
  /// Disable MaterialApp's debugShowCheckedModeBanner when using this option:
  /// its full-window CustomPaint otherwise masks the entire screen.
  ///
  /// Frames containing a painter whose bounds cannot be determined, such as a
  /// zero-sized CustomPaint, are skipped rather than sent with a missing mask.
  var maskCustomPaint = false;

  /// Decides, per text node, what to mask — instead of all-or-nothing.
  ///
  /// When set, every plain `Text`, `RichText`, and non-sensitive text input is
  /// masked according to the [PostHogTextMask] the policy returns for its
  /// rendered string, and [maskAllTexts] no longer applies to those nodes.
  /// Ranges are masked at glyph precision, so a policy can hide an amount
  /// while the label next to it stays readable:
  ///
  /// ```dart
  /// // Mask numbers only: "Balance ₦2,450,000.00" keeps "Balance" visible.
  /// config.sessionReplayConfig.textMaskPolicy =
  ///     PostHogTextMaskPolicies.digits();
  ///
  /// // Mask everything except a known-safe pattern.
  /// config.sessionReplayConfig.textMaskPolicy =
  ///     PostHogTextMaskPolicies.reveal(RegExp(r'^(Continue|Cancel)$'));
  ///
  /// // Or decide per node, using its text, its widget, or both — here, two
  /// // nodes with the same string are told apart by style.
  /// config.sessionReplayConfig.textMaskPolicy = (text, widget) =>
  ///     widget is RichText && widget.text.style?.fontWeight == FontWeight.bold
  ///         ? const PostHogTextMask.none()
  ///         : const PostHogTextMask.all();
  /// ```
  ///
  /// [widget] is whichever widget actually produced the render object being
  /// captured — `RichText` for `Text` and `RichText` alike, `EditableText`
  /// for text inputs. It is not the outer `Text`/`TextField` an app writes:
  /// `Text` is a thin wrapper over `RichText`, and there is no reliable way
  /// to recover it across Flutter's internal composition. Reach for its
  /// style, its `InlineSpan`, or (for inputs) properties like `obscureText`
  /// and `readOnly` — not its `key`, which will be the framework's, not the
  /// app's.
  ///
  /// Precedence, highest first: sensitive inputs (`obscureText`, password,
  /// card, and other sensitive autofill hints) are always fully masked;
  /// `PostHogMaskWidget` masks and `PostHogUnmaskWidget` reveals its subtree
  /// without consulting the policy; then the policy decides; [maskAllTexts]
  /// only applies to text nodes when no policy is set.
  ///
  /// The policy runs on the UI thread for every captured text node; keep it
  /// fast. It applies to the Flutter widget tree only — text on captured
  /// native screens still follows [maskAllTexts], and custom-painted text
  /// still needs [maskCustomPaint]. Can be changed at runtime; the next
  /// frame uses the new policy.
  ///
  /// It fails closed. Where glyph-precise rects can't be trusted to cover
  /// everything the decision asked to hide, the whole node is masked
  /// instead:
  ///
  ///  * the policy throws, or its ranges throw while being read;
  ///  * a range falls outside the text, or cuts into a grapheme cluster —
  ///    Flutter lays out no box for the severed half, so it would otherwise
  ///    stay readable;
  ///  * the node's style paints `shadows`, which selection boxes don't
  ///    bound, so a masked glyph could leave a readable copy of itself
  ///    wherever its shadow lands;
  ///  * the node is a paragraph containing a `WidgetSpan` and the decision
  ///    yields anything other than exactly one rect — including
  ///    `PostHogTextMask.none()` and `PostHogTextMask.only([])`. A
  ///    `PostHogUnmaskWidget` nested in that paragraph still reveals its
  ///    own subtree.
  ///
  /// Default: null.
  PostHogTextMaskPolicy? textMaskPolicy;

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

  /// Multiplier for the width and height of Android replay screenshots.
  ///
  /// Flutter screenshots scale from their logical-resolution baseline; native
  /// screens recorded with [captureNativeScreens] scale from physical resolution.
  /// Defaults to `1.0`. Values are clamped to `0.1`–`1.0`; NaN and infinity use
  /// `1.0`. Scaled dimensions round up to at least one pixel without changing the
  /// logical replay viewport. Masks round outward to cover output pixels; frames
  /// with mask bounds that cannot be mapped safely are skipped.
  /// Set before `Posthog().setup(config)`.
  @experimental
  double get screenshotScale => _screenshotScale;
  double _screenshotScale = 1.0;

  @experimental
  set screenshotScale(double value) {
    _screenshotScale = value.isFinite ? value.clamp(0.1, 1.0) : 1.0;
  }

  /// Compression quality for Android replay screenshots.
  ///
  /// Flutter screenshots use JPEG; native screens recorded with
  /// [captureNativeScreens] use WebP. Defaults to `30`, clamped to `0`–`100`.
  /// Higher values generally retain more detail and produce larger payloads.
  /// Native capture on Android 10 uses lossless WebP at quality `100`; other
  /// supported versions use lossy WebP. Does not change resolution.
  /// Set before `Posthog().setup(config)`.
  @experimental
  int get screenshotCompressionQuality => _screenshotCompressionQuality;
  int _screenshotCompressionQuality = 30;

  @experimental
  set screenshotCompressionQuality(int value) {
    _screenshotCompressionQuality = value.clamp(0, 100);
  }

  /// Pixel format for Android native-screen captures.
  ///
  /// Applies only to screens recorded with [captureNativeScreens].
  /// Defaults to [PostHogScreenshotColorMode.argb8888].
  /// Set before `Posthog().setup(config)`.
  @experimental
  var screenshotColorMode = PostHogScreenshotColorMode.argb8888;

  /// Mask all platform views (WebView, Maps, etc.) in session replay.
  ///
  /// Default: true.
  ///
  /// When true, every platform view is covered with a black rectangle in
  /// session replay screenshots. Set to false to opt out globally, or wrap
  /// individual views with [PostHogPlatformView] for per-view control.
  ///
  /// Setting this false reveals every texture-backed view, including camera
  /// previews (e.g. the `camera` plugin) — prefer per-view
  /// [PostHogPlatformView] opt-ins over the global opt-out.
  ///
  /// **iOS note:** among `UiKitView`s, setting this false only reveals
  /// [WKWebView]-backed ones; maps, ARKit and other native views stay masked.
  /// See [PostHogPlatformViewPrivacy.capture].
  ///
  /// Applies only to native views embedded in the Flutter layout. For native
  /// screens presented over the whole app, see [captureNativeScreens].
  var maskAllPlatformViews = true;

  /// Capture native screens that cover the Flutter UI (full-screen paywalls,
  /// presented view controllers, native activities) via the native replay
  /// SDK, so they appear in replay instead of a frozen Flutter frame.
  /// When enabled and a detected screen cannot be captured, a single black
  /// placeholder frame is sent instead; if that also fails, replay keeps
  /// showing the last Flutter frame. With this flag off there is no
  /// placeholder — nothing about replay changes.
  ///
  /// Only full-screen, same-process screens are detected. Not captured:
  /// partial-height sheets (e.g. Apple Pay, share sheet), other-process
  /// content, Android dialogs/Custom Tabs, and iOS covers without an opaque
  /// background — replay keeps showing the covered Flutter UI for those.
  ///
  /// Opt-in: enabling this starts a lightweight occlusion detector. When false
  /// (the default), the covered Flutter tree keeps recording, as before.
  ///
  /// Captured native frames honor your [maskAllTexts] / [maskAllImages]
  /// settings — with the defaults (both true) all native text and images are
  /// masked; setting either false reveals it on native screens too.
  ///
  /// Applies only to native screens presented over the whole app. For native
  /// views embedded in the Flutter layout, see [maskAllPlatformViews].
  ///
  /// Can be changed at runtime after setup — turning it off before presenting
  /// a sensitive native screen guarantees that screen is not captured.
  ///
  /// Default: false. Requires native SDK support for on-demand capture.
  bool get captureNativeScreens => _captureNativeScreens;

  bool _captureNativeScreens = false;

  set captureNativeScreens(bool value) {
    if (_captureNativeScreens == value) {
      return;
    }
    _captureNativeScreens = value;
    // Propagated immediately (not lazily at the next episode) so a toggle-off
    // right before presenting a native screen can never race the detector into
    // capturing it. Before setup the value crosses inside the config instead.
    if (identical(Posthog().config?.sessionReplayConfig, this)) {
      PosthogFlutterPlatformInterface.instance.setCaptureNativeScreens(value);
    }
  }

  /// Verify that masks remain aligned while capturing session replay screenshots.
  ///
  /// Android only. This applies only to native-screen captures enabled by
  /// [captureNativeScreens]. Normal Flutter widget screenshots are rendered and
  /// masked by Flutter and are unaffected.
  ///
  /// Enabling this can preserve screenshots during pixel-only redraws, including
  /// continuously animated content, but performs additional view hierarchy walks
  /// while a screenshot is captured.
  ///
  /// Default: false.
  var verifyScreenshotMaskAlignment = false;

  /// Converts this session replay configuration to a platform-channel map.
  ///
  /// Returns values consumed by the Android and Apple session replay
  /// implementations.
  Map<String, dynamic> toMap() {
    return {
      'captureTouches': captureTouches,
      'maskAllImages': maskAllImages,
      'maskAllTexts': maskAllTexts,
      'throttleDelayMs': throttleDelay.inMilliseconds,
      'maskAllPlatformViews': maskAllPlatformViews,
      'captureNativeScreens': captureNativeScreens,
      'verifyScreenshotMaskAlignment': verifyScreenshotMaskAlignment,
      'screenshotScale': screenshotScale,
      'screenshotCompressionQuality': screenshotCompressionQuality,
      'screenshotColorMode': screenshotColorMode.name,
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
  /// Captures Java/Kotlin exceptions. For native C/C++ (NDK) crashes, also
  /// enable [captureNativeCrashes].
  ///
  /// Stacktrace demangling for minified builds is supported by installing
  /// the PostHog Gradle plugin to upload ProGuard/R8 mappings.
  /// See: https://posthog.com/docs/error-tracking/upload-mappings/android
  ///
  /// Default: false
  var captureNativeExceptions = false;

  /// Enable automatic capture of native C/C++ (NDK) crashes on Android.
  ///
  /// Requires Android 12 (API 31) or later. A native crash kills the process
  /// immediately, so the crash is captured on the next app launch from the
  /// records the OS kept, as an `$exception` event with raw native stack
  /// frames. Exception autocapture must also be enabled in the project's
  /// error tracking settings.
  ///
  /// For symbolicated stack traces, upload the app's `.so` debug symbols with
  /// the PostHog Gradle plugin.
  /// See: https://posthog.com/docs/error-tracking/upload-mappings/android
  ///
  /// Because the event is sent from the next launch, properties like
  /// `$app_version` reflect the app at capture time, not at crash time.
  ///
  /// **Note:**
  /// - Apple platforms: Not applicable (native crash capture is part of
  ///   [captureNativeExceptions])
  /// - Flutter web: Not supported
  ///
  /// Default: false
  var captureNativeCrashes = false;

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
      'captureNativeCrashes': captureNativeCrashes,
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
