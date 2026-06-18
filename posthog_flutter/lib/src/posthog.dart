import 'package:flutter/foundation.dart';
// ignore: unnecessary_import
import 'package:meta/meta.dart';

import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_exception.dart';
import 'feature_flag_result.dart';
import 'logs/posthog_log_record.dart';
import 'logs/posthog_log_severity.dart';
import 'logs/posthog_logger.dart';
import 'posthog_config.dart';
import 'posthog_flutter_platform_interface.dart';
import 'posthog_internal_events.dart';
import 'posthog_observer.dart';
import 'utils/before_send.dart';

/// Entry point for the PostHog Flutter SDK.
///
/// Use the singleton returned by [Posthog] to set up the SDK, capture events,
/// identify users, evaluate feature flags, and control session replay.
class Posthog {
  static PosthogFlutterPlatformInterface get _posthog =>
      PosthogFlutterPlatformInterface.instance;

  static final _instance = Posthog._internal();

  PostHogConfig? _config;

  /// Returns the singleton PostHog client instance.
  factory Posthog() {
    return _instance;
  }

  String? _currentScreen;

  /// Initializes the PostHog SDK.
  ///
  /// This method sets up the connection to your PostHog instance and prepares
  /// the SDK for tracking events and feature flags.
  ///
  /// The [config] object contains your project token, host, and other settings.
  /// To listen for feature flag load events, provide an `onFeatureFlags`
  /// callback in the [PostHogConfig].
  ///
  /// Returns a [Future] that completes when platform setup has finished.
  ///
  /// **Example:**
  /// ```dart
  /// final config = PostHogConfig('YOUR_PROJECT_TOKEN');
  /// config.host = 'YOUR_POSTHOG_HOST';
  /// config.onFeatureFlags = () {
  ///   // Feature flags are now loaded, you can read flag values here
  /// };
  /// await Posthog().setup(config);
  /// ```
  ///
  /// For Android and iOS, if you are performing a manual setup,
  /// ensure `com.posthog.posthog.AUTO_INIT: false` is set in your native
  /// configuration.
  Future<void> setup(PostHogConfig config) {
    if (config.projectToken.isEmpty) {
      debugPrint(
        '[PostHog] projectToken must not be blank. Setup skipped.',
      );
      return Future<void>.value();
    }

    _config = config; // Store the config

    if (config.sessionReplay) {
      PostHogInternalEvents.sessionRecordingActive.value = true;
    }

    _installFlutterIntegrations(config);

    return _posthog.setup(config);
  }

  void _installFlutterIntegrations(PostHogConfig config) {
    // Install exception autocapture if enabled
    if (config.errorTrackingConfig.captureFlutterErrors ||
        config.errorTrackingConfig.capturePlatformDispatcherErrors ||
        config.errorTrackingConfig.captureIsolateErrors) {
      PostHogErrorTrackingAutoCaptureIntegration.install(
        config: config.errorTrackingConfig,
        posthog: _posthog,
      );
    }
  }

  void _uninstallFlutterIntegrations() {
    // Uninstall exception autocapture integration
    PostHogErrorTrackingAutoCaptureIntegration.uninstall();
  }

  /// The active SDK configuration, if [setup] has completed.
  ///
  /// For internal use by Flutter integrations.
  @internal
  PostHogConfig? get config => _config;

  /// Returns the current screen name or route name.
  ///
  /// Only returns a value if [PosthogObserver] is used.
  @internal
  String? get currentScreen => _currentScreen;

  /// Associates events with a specific user.
  ///
  /// The [userId] is a unique identifier for your user, typically their email or
  /// database ID.
  ///
  /// The optional [userProperties] are person properties set with `$set`.
  ///
  /// The optional [userPropertiesSetOnce] are person properties set with
  /// `$set_once`.
  ///
  /// Returns a [Future] that completes when the identify call has been queued.
  ///
  /// **Example:**
  /// ```dart
  /// await Posthog().identify(
  ///   userId: emailController.text,
  ///   userProperties: {"name": "Peter Griffin", "email": "peter@familyguy.com"},
  ///   userPropertiesSetOnce: {"date_of_first_log_in": "2024-03-01"}
  /// );
  /// ```
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) =>
      _posthog.identify(
        userId: userId,
        userProperties: userProperties,
        userPropertiesSetOnce: userPropertiesSetOnce,
      );

  /// Sets person properties for the current user without requiring identify.
  ///
  /// This method sends person property updates without changing the current
  /// distinct ID.
  ///
  /// The optional [userPropertiesToSet] values are set with `$set` and overwrite
  /// existing values.
  ///
  /// The optional [userPropertiesToSetOnce] values are set with `$set_once` and
  /// do not overwrite existing values.
  ///
  /// Returns a [Future] that completes when the update has been queued.
  /// If both property maps are null or empty, no event is queued.
  ///
  /// **Example:**
  /// ```dart
  /// await Posthog().setPersonProperties(
  ///   userPropertiesToSet: {"name": "John Doe", "email": "john@example.com"},
  ///   userPropertiesToSetOnce: {"date_of_first_login": "2024-03-01"}
  /// );
  /// ```
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
  }) =>
      _posthog.setPersonProperties(
        userPropertiesToSet: userPropertiesToSet,
        userPropertiesToSetOnce: userPropertiesToSetOnce,
      );

  /// Captures a custom event.
  ///
  /// Docs: https://posthog.com/docs/product-analytics/user-properties
  ///
  /// We recommend using an `[object] [verb]` format for [eventName], where the
  /// object is the entity that the behavior relates to and the verb is the
  /// behavior itself. For example: `project created`, `user signed up`, or
  /// `invite sent`.
  ///
  /// The optional [properties] are event properties.
  ///
  /// The optional [userProperties] are person properties set with `$set`.
  ///
  /// The optional [userPropertiesSetOnce] are person properties set with
  /// `$set_once`.
  ///
  /// Returns a [Future] that completes when the event has been queued.
  ///
  /// **Example**
  /// ```dart
  ///   await Posthog().capture(
  ///    eventName: 'user_signed_up',
  ///    properties: {
  ///      'login_type': 'email',
  ///      'is_free_trial': true
  ///    }
  ///   );
  /// ```
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) {
    final propertiesCopy = properties == null ? null : {...properties};

    final currentScreen = _currentScreen;
    if (propertiesCopy != null &&
        !propertiesCopy.containsKey('\$screen_name') &&
        currentScreen != null) {
      propertiesCopy['\$screen_name'] = currentScreen;
    }
    return _posthog.capture(
      eventName: eventName,
      properties: propertiesCopy,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );
  }

  /// Captures a screen view event.
  ///
  /// The [screenName] is the screen title or route name.
  ///
  /// The optional [properties] are additional screen event properties.
  ///
  /// Returns a [Future] that completes when the screen event has been queued.
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) {
    _currentScreen = screenName;
    return _posthog.screen(screenName: screenName, properties: properties);
  }

  /// Captures a structured log record.
  ///
  /// Docs: https://posthog.com/docs/logs
  ///
  /// `captureLog` is not gated by remote config.
  ///
  /// The [body] is the log message. A blank body is dropped before
  /// [PostHogLogsConfig.beforeSend] runs.
  ///
  /// The optional [level] is the severity, defaulting to
  /// [PostHogLogSeverity.info].
  ///
  /// The optional [attributes] are per-record attributes (e.g. request id,
  /// duration). Values must be supported by the platform channel serializer.
  ///
  /// The optional [traceId], [spanId], and [traceFlags] are W3C distributed
  /// tracing fields used to correlate a log with a trace. [traceId] is a
  /// 32-character lowercase hex string, [spanId] is 16 characters, and
  /// [traceFlags] is a bitfield whose bit 0 is the `sampled` flag (an explicit
  /// `0` is emitted; `null` omits the field). They pass through unchanged and
  /// are not visible to [PostHogLogsConfig.beforeSend].
  ///
  /// Auto-captured context (distinct id, session id, screen name, app state,
  /// active feature flags) is added by the native SDK.
  ///
  /// Records are passed through [PostHogLogsConfig.beforeSend] before being
  /// forwarded to the native SDK; a callback may modify or drop them.
  ///
  /// Returns a [Future] that completes when the record has been forwarded.
  ///
  /// **Example:**
  /// ```dart
  /// await Posthog().captureLog(
  ///   body: 'checkout completed',
  ///   level: PostHogLogSeverity.info,
  ///   attributes: {'order_id': 'ord_789'},
  /// );
  /// ```
  Future<void> captureLog({
    required String body,
    PostHogLogSeverity level = PostHogLogSeverity.info,
    Map<String, Object>? attributes,
    String? traceId,
    String? spanId,
    int? traceFlags,
  }) async {
    if (body.trim().isEmpty) {
      return;
    }

    var record = PostHogLogRecord(
      body: body,
      level: level,
      attributes: attributes == null ? null : {...attributes},
    );

    final callbacks =
        _config?.logsConfig.beforeSend ?? const <BeforeSendLogCallback>[];
    for (final callback in callbacks) {
      try {
        final result = await runBeforeSend<PostHogLogRecord>(callback, record);
        if (result == null) {
          debugPrint('[PostHog] Log dropped by beforeSend');
          return;
        }
        record = result;
      } catch (e) {
        debugPrint('[PostHog] beforeSend threw, dropping log: $e');
        return;
      }
    }

    // A beforeSend callback may have blanked the body, which drops the record.
    if (record.body.trim().isEmpty) {
      return;
    }

    return _posthog.captureLog(
      body: record.body,
      level: record.level,
      attributes: record.attributes,
      traceId: traceId,
      spanId: spanId,
      traceFlags: traceFlags,
    );
  }

  PostHogLogger? _logger;

  /// Per-level logger facade for capturing structured logs.
  ///
  /// Each helper delegates to [captureLog] with the matching severity. Built
  /// once on first access and cached.
  ///
  /// **Example:**
  /// ```dart
  /// Posthog().logger.info('user signed in', {'method': 'google'});
  /// Posthog().logger.error('payment failed', {'error_code': 'E001'});
  /// ```
  PostHogLogger get logger => _logger ??= PostHogLogger(
        (body, level, attributes) =>
            captureLog(body: body, level: level, attributes: attributes),
      );

  /// Creates an alias for the current user.
  ///
  /// Docs:
  /// https://posthog.com/docs/product-analytics/identify#alias-assigning-multiple-distinct-ids-to-the-same-user
  ///
  /// The [alias] is the additional distinct ID to associate with the user.
  ///
  /// Returns a [Future] that completes when the alias call has been queued.
  Future<void> alias({required String alias}) => _posthog.alias(alias: alias);

  /// Returns the registered `distinctId` property.
  ///
  /// Returns an empty string if the platform cannot provide a distinct ID.
  Future<String> getDistinctId() => _posthog.getDistinctId();

  /// Resets all cached properties including the `distinctId`.
  ///
  /// The SDK will behave as if it has been [setup] for the first time.
  ///
  /// Returns a [Future] that completes when the reset request has been queued.
  Future<void> reset() => _posthog.reset();

  /// Disables data collection for the current user.
  ///
  /// Returns a [Future] that completes when the opt-out request has been queued.
  Future<void> disable() {
    // Uninstall Flutter-specific integrations when disabling
    _uninstallFlutterIntegrations();

    return _posthog.disable();
  }

  /// Enables data collection for the current user.
  ///
  /// Returns a [Future] that completes when the opt-in request has been queued.
  Future<void> enable() {
    final config = _config;
    if (config != null) {
      _installFlutterIntegrations(config);
    }

    return _posthog.enable();
  }

  /// Returns whether the current user has opted out of data collection.
  Future<bool> isOptOut() => _posthog.isOptOut();

  /// Enables or disables verbose logs about the inner workings of the SDK.
  ///
  /// Set [enabled] to `true` to enable debug logs, or `false` to disable them.
  ///
  /// Returns a [Future] that completes when the debug setting has been applied.
  Future<void> debug(bool enabled) => _posthog.debug(enabled);

  /// Registers a super property sent with all following events.
  ///
  /// The property remains active until [unregister] is called with the same
  /// [key]. The [value] must be supported by the platform channel serializer.
  ///
  /// Returns a [Future] that completes when the property has been registered.
  Future<void> register(String key, Object value) =>
      _posthog.register(key, value);

  /// Unregisters a previously registered super property.
  ///
  /// The [key] identifies the property to stop sending with future events.
  ///
  /// Returns a [Future] that completes when the property has been removed.
  Future<void> unregister(String key) => _posthog.unregister(key);

  /// Returns whether a boolean feature flag is enabled.
  ///
  /// Docs: https://posthog.com/docs/feature-flags and
  /// https://posthog.com/docs/experiments
  ///
  /// The [key] is the feature flag key.
  ///
  /// Returns `false` when the flag is disabled, missing, or not a boolean flag.
  Future<bool> isFeatureEnabled(String key) => _posthog.isFeatureEnabled(key);

  /// Reloads feature flags for the current user.
  ///
  /// Returns a [Future] that completes when the reload request has been queued.
  Future<void> reloadFeatureFlags() => _posthog.reloadFeatureFlags();

  /// Sets person properties that are used only for feature flag evaluation.
  ///
  /// Docs: https://posthog.com/docs/feature-flags
  ///
  /// Unlike [setPersonProperties], this does **not** enqueue a `$set` event. The
  /// properties are sent inline with the next feature flag evaluation request,
  /// so flags that target these properties can be evaluated immediately without
  /// waiting for the `$set` event to be ingested into the person store.
  ///
  /// The [userProperties] are merged with any previously set values; matching
  /// keys are overwritten. If [userProperties] is empty, this is a no-op.
  ///
  /// Set [reloadFeatureFlags] to `false` to skip reloading flags after updating
  /// the properties (defaults to `true`). When `true`, the returned [Future]
  /// awaits the reload before completing; on iOS and Android this means flags
  /// have finished loading, so the next [getFeatureFlag] / [getFeatureFlagResult]
  /// reflects the updated properties. On web the reload is best-effort.
  ///
  /// **Example:**
  /// ```dart
  /// await Posthog().setPersonPropertiesForFlags({
  ///   "storefront_country": "US",
  ///   "superwall_demand_score": 88,
  /// });
  /// final result = await Posthog().getFeatureFlagResult("my_flag");
  /// ```
  Future<void> setPersonPropertiesForFlags(
    Map<String, Object> userProperties, {
    bool reloadFeatureFlags = true,
  }) async {
    if (userProperties.isEmpty) {
      return;
    }
    await _posthog.setPersonPropertiesForFlags(userProperties);
    if (reloadFeatureFlags) {
      await this.reloadFeatureFlags();
    }
  }

  /// Clears all person properties that were set for feature flag evaluation via
  /// [setPersonPropertiesForFlags].
  ///
  /// Set [reloadFeatureFlags] to `false` to skip reloading flags after clearing
  /// the properties (defaults to `true`). When `true`, the returned [Future]
  /// awaits the reload before completing (on iOS/Android, after flags finish
  /// loading; on web, best-effort).
  Future<void> resetPersonPropertiesForFlags({
    bool reloadFeatureFlags = true,
  }) async {
    await _posthog.resetPersonPropertiesForFlags();
    if (reloadFeatureFlags) {
      await this.reloadFeatureFlags();
    }
  }

  /// Sets properties for a specific [groupType] that are used only for feature
  /// flag evaluation.
  ///
  /// The properties are sent inline with the next feature flag evaluation
  /// request, so flags that target group properties can be evaluated without
  /// waiting for ingestion.
  ///
  /// The [groupProperties] are merged with any previously set values for the
  /// same [groupType]; matching keys are overwritten. If [groupProperties] is
  /// empty, this is a no-op.
  ///
  /// Set [reloadFeatureFlags] to `false` to skip reloading flags after updating
  /// the properties (defaults to `true`). When `true`, the returned [Future]
  /// awaits the reload before completing (on iOS/Android, after flags finish
  /// loading; on web, best-effort).
  ///
  /// **Example:**
  /// ```dart
  /// await Posthog().setGroupPropertiesForFlags(
  ///   "organization",
  ///   {"name": "ACME Corp", "is_enterprise": true},
  /// );
  /// ```
  Future<void> setGroupPropertiesForFlags(
    String groupType,
    Map<String, Object> groupProperties, {
    bool reloadFeatureFlags = true,
  }) async {
    if (groupProperties.isEmpty) {
      return;
    }
    await _posthog.setGroupPropertiesForFlags(groupType, groupProperties);
    if (reloadFeatureFlags) {
      await this.reloadFeatureFlags();
    }
  }

  /// Clears group properties that were set for feature flag evaluation via
  /// [setGroupPropertiesForFlags].
  ///
  /// If [groupType] is provided, only properties for that group type are
  /// cleared; otherwise all group properties are cleared.
  ///
  /// Set [reloadFeatureFlags] to `false` to skip reloading flags after clearing
  /// the properties (defaults to `true`). When `true`, the returned [Future]
  /// awaits the reload before completing (on iOS/Android, after flags finish
  /// loading; on web, best-effort).
  Future<void> resetGroupPropertiesForFlags({
    String? groupType,
    bool reloadFeatureFlags = true,
  }) async {
    await _posthog.resetGroupPropertiesForFlags(groupType: groupType);
    if (reloadFeatureFlags) {
      await this.reloadFeatureFlags();
    }
  }

  /// Associates the current user with a group.
  ///
  /// Docs: https://posthog.com/docs/product-analytics/group-analytics
  ///
  /// The [groupType] is the group type, such as `company`.
  ///
  /// The [groupKey] is the unique key for the group.
  ///
  /// The optional [groupProperties] are group properties set with `$group_set`.
  ///
  /// Returns a [Future] that completes when the group call has been queued.
  ///
  /// **Example:**
  /// ```dart
  /// await Posthog().group(
  ///  groupType: "company",
  ///  groupKey: "company_id_in_your_db",
  ///  groupProperties: {
  ///    "name": "ACME Corp"
  /// });
  /// ```
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) =>
      _posthog.group(
        groupType: groupType,
        groupKey: groupKey,
        groupProperties: groupProperties,
      );

  /// Returns the feature flag value for [key].
  ///
  /// Returns `null` if the flag does not exist or cannot be loaded. For boolean
  /// flags, returns `true` or `false`. For multivariate flags, returns the
  /// variant key.
  Future<Object?> getFeatureFlag(String key) =>
      _posthog.getFeatureFlag(key: key);

  /// Returns the full feature flag result for [key], including value and
  /// payload.
  ///
  /// This is the canonical method for getting feature flag data.
  /// Returns `null` if the flag does not exist or cannot be loaded.
  ///
  /// Set [sendEvent] to `false` to suppress the `$feature_flag_called` event.
  /// This is useful when you only need the payload and do not want to emit the
  /// event.
  ///
  /// **Example:**
  /// ```dart
  /// final result = await Posthog().getFeatureFlagResult('my-flag');
  /// if (result != null && result.enabled) {
  ///   final variant = result.variant; // For multivariate flags
  ///   final payload = result.payload; // Associated payload data
  /// }
  /// ```
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult(
    String key, {
    bool sendEvent = true,
  }) =>
      _posthog.getFeatureFlagResult(key: key, sendEvent: sendEvent);

  /// Returns the payload for the feature flag [key].
  ///
  /// Returns `null` when the flag does not exist, has no payload, or the payload
  /// cannot be loaded.
  @Deprecated(
    'Use getFeatureFlagResult instead, which returns both value and payload.',
  )
  Future<Object?> getFeatureFlagPayload(String key) =>
      _posthog.getFeatureFlagPayload(key: key);

  /// Flushes queued events immediately where supported by the platform.
  ///
  /// Returns a [Future] that completes when the flush request has finished.
  Future<void> flush() => _posthog.flush();

  /// Captures an exception with optional custom properties.
  ///
  /// The [error] is the error or exception to capture.
  ///
  /// The optional [stackTrace] is attached to the exception. If omitted, the
  /// current stack trace is used by the exception processor where possible.
  ///
  /// The optional [properties] are added to the `$exception` event.
  ///
  /// Returns a [Future] that completes when the exception event has been queued.
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) =>
      _posthog.captureException(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
      );

  /// Captures a `runZonedGuarded` error with optional custom properties.
  ///
  /// See: https://api.flutter.dev/flutter/dart-async/runZonedGuarded.html
  ///
  /// The [error] is the error or exception received by `runZonedGuarded`.
  ///
  /// The optional [stackTrace] is attached to the exception. If omitted, the
  /// current stack trace is used by the exception processor where possible.
  ///
  /// The optional [properties] are added to the `$exception` event.
  ///
  /// Returns a [Future] that completes when the exception event has been queued.
  Future<void> captureRunZonedGuardedError({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {
    final wrappedError = PostHogException(
      source: error,
      mechanism: 'runZonedGuarded',
      handled: false,
    );
    await _posthog.captureException(
      error: wrappedError,
      stackTrace: stackTrace,
      properties: properties,
    );
  }

  /// Records an exception step (breadcrumb-style context record).
  ///
  /// Steps accumulate in a rolling, byte-bounded buffer and are attached to
  /// every captured `$exception` event as `$exception_steps`, giving the
  /// PostHog error-tracking UI a timeline of recent activity leading up to each
  /// error. The buffer rotates only by byte-budget eviction (see
  /// [PostHogExceptionStepsConfig.maxBytes]) and is not cleared by a capture or
  /// an identity change.
  ///
  /// The buffer is owned by the embedded native SDK, so steps also survive
  /// native fatal crashes and attach to the crash `$exception` reported on the
  /// next launch.
  ///
  /// The [message] is a short, non-empty description of what happened; an empty
  /// or whitespace-only message is ignored. The optional [properties] are
  /// additional context. The reserved keys `$message` and `$timestamp` are
  /// stripped — the SDK sets the canonical values, including a timestamp
  /// captured when the step is recorded.
  ///
  /// Recording never throws into your app and does not block the caller.
  ///
  /// **Note:**
  /// - Flutter web: forwarded to posthog-js. Steps attach to exceptions
  ///   captured by posthog-js, but not to exceptions captured via
  ///   [captureException] on web.
  ///
  /// **Example:**
  /// ```dart
  /// Posthog().addExceptionStep(
  ///   'User tapped Checkout',
  ///   properties: {'screen': 'cart'},
  /// );
  /// ```
  Future<void> addExceptionStep(
    String message, {
    Map<String, Object>? properties,
  }) {
    if (message.trim().isEmpty) {
      debugPrint('[PostHog] addExceptionStep called with an empty message.');
      return Future<void>.value();
    }
    // Honor the documented no-op contract on every platform: native enforces
    // `enabled` via the config forwarded at setup, but on web `setup` doesn't
    // push it to posthog-js, so guard here too.
    if (_config?.errorTrackingConfig.exceptionSteps.enabled == false) {
      return Future<void>.value();
    }
    return _posthog.addExceptionStep(message, properties: properties);
  }

  /// Closes the PostHog SDK and cleans up resources.
  ///
  /// Returns a [Future] that completes when platform resources have been closed.
  ///
  /// **Note:** After calling `close()`, surveys will not be rendered until the
  /// SDK is re-initialized and the next navigation event occurs.
  Future<void> close() {
    _config = null;
    _currentScreen = null;
    PostHogInternalEvents.sessionRecordingActive.value = false;
    PosthogObserver.clearCurrentContext();

    // Uninstall Flutter integrations
    _uninstallFlutterIntegrations();

    return _posthog.close();
  }

  /// Returns the session ID if a session is active.
  ///
  /// Returns `null` when no session is active or the platform cannot provide a
  /// session ID.
  Future<String?> getSessionId() => _posthog.getSessionId();

  /// Starts session recording.
  ///
  /// This method will have no effect if PostHog is not enabled, or if session
  /// replay is disabled in your project settings.
  ///
  /// Set [resumeCurrent] to `true` (the default) to resume recording the current
  /// session. Set it to `false` to start a new session and begin recording.
  ///
  /// Returns a [Future] that completes when the start request has been sent.
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    await _posthog.startSessionRecording(resumeCurrent: resumeCurrent);
    PostHogInternalEvents.sessionRecordingActive.value = true;
  }

  /// Stops the current session recording if one is in progress.
  ///
  /// This method will have no effect if PostHog is not enabled.
  ///
  /// Returns a [Future] that completes when the stop request has been sent.
  Future<void> stopSessionRecording() async {
    await _posthog.stopSessionRecording();
    PostHogInternalEvents.sessionRecordingActive.value = false;
  }

  /// Returns whether session replay is currently active.
  ///
  /// Returns `false` when session replay is inactive or unsupported by the
  /// current platform.
  Future<bool> isSessionReplayActive() => _posthog.isSessionReplayActive();

  Posthog._internal();
}
