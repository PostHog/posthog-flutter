import 'package:flutter/foundation.dart';
// ignore: unnecessary_import
import 'package:meta/meta.dart';

import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_exception.dart';
import 'feature_flag_result.dart';
import 'posthog_config.dart';
import 'posthog_flutter_io.dart';
import 'posthog_flutter_platform_interface.dart';
import 'posthog_internal_events.dart';
import 'posthog_observer.dart';

class Posthog {
  static PosthogFlutterPlatformInterface get _posthog =>
      PosthogFlutterPlatformInterface.instance;

  static final _instance = Posthog._internal();

  PostHogConfig? _config;

  factory Posthog() {
    return _instance;
  }

  String? _currentScreen;

  /// Initializes the PostHog SDK.
  ///
  /// This method sets up the connection to your PostHog instance and prepares the SDK for tracking events and feature flags.
  ///
  /// - [config]: The [PostHogConfig] object containing your API key, host, and other settings.
  ///   To listen for feature flag load events, provide an `onFeatureFlags` callback in the [PostHogConfig].
  ///
  /// **Example:**
  /// ```dart
  /// final config = PostHogConfig('YOUR_API_KEY');
  /// config.host = 'YOUR_POSTHOG_HOST';
  /// config.onFeatureFlags = () {
  ///   // Feature flags are now loaded, you can read flag values here
  /// };
  /// // Or use the new callback with flag data:
  /// config.onFeatureFlagsLoaded = (flags) {
  ///   // flags contains all loaded feature flags
  /// };
  /// await Posthog().setup(config);
  /// ```
  ///
  /// For Android and iOS, if you are performing a manual setup,
  /// ensure `com.posthog.posthog.AUTO_INIT: false` is set in your native configuration.
  Future<void> setup(PostHogConfig config) {
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
        config.errorTrackingConfig.capturePlatformDispatcherErrors) {
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

  @internal
  PostHogConfig? get config => _config;

  /// Returns the current screen name (or route name)
  /// Only returns a value if [PosthogObserver] is used
  @internal
  String? get currentScreen => _currentScreen;

  /// Can associate events with specific users
  ///
  /// - [userId] A unique identifier for your user. Typically either their email or database ID.
  /// - [userProperties] the user properties, set as a "$set" property,
  /// - [userPropertiesSetOnce] the user properties to set only once, set as a "$set_once" property.
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
          userPropertiesSetOnce: userPropertiesSetOnce);

  /// Sets person properties for the current user without requiring identify.
  ///
  /// This method sends a `$set` event to update person properties.
  ///
  /// - [userPropertiesToSet] the user properties to set, will overwrite existing values
  /// - [userPropertiesToSetOnce] the user properties to set only once, will not overwrite existing values
  ///
  /// Returns early without sending an event if both property maps are null or empty.
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

  /// Captures events.
  /// Docs https://posthog.com/docs/product-analytics/user-properties
  ///
  /// We recommend using a [object] [verb] format for your event names,
  /// where [object] is the entity that the behavior relates to,
  /// and [verb] is the behavior itself.
  /// For example, project created, user signed up, or invite sent.
  ///
  /// - [eventName] name of event
  /// - [properties] the custom properties
  /// - [userProperties] the user properties, set as a "$set" property,
  /// - [userPropertiesSetOnce] the user properties to set only once, set as a "$set_once" property.
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

  /// Captures a screen view event
  ///
  /// - [screenName] the screen title
  /// - [properties] the custom properties
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) {
    _currentScreen = screenName;
    return _posthog.screen(
      screenName: screenName,
      properties: properties,
    );
  }

  /// Creates an alias for the user.
  /// Docs https://posthog.com/docs/product-analytics/identify#alias-assigning-multiple-distinct-ids-to-the-same-user
  ///
  /// - [alias] the alias
  Future<void> alias({
    required String alias,
  }) =>
      _posthog.alias(
        alias: alias,
      );

  /// Returns the registered `distinctId` property
  Future<String> getDistinctId() => _posthog.getDistinctId();

  /// Resets all the cached properties including the `distinctId`.
  ///
  /// The SDK will behave as its been [setup] for the first time
  Future<void> reset() => _posthog.reset();

  /// Disable data collection for a user
  Future<void> disable() {
    // Uninstall Flutter-specific integrations when disabling
    _uninstallFlutterIntegrations();

    return _posthog.disable();
  }

  /// Enable data collection for a user
  Future<void> enable() => _posthog.enable();

  /// Check if the user has opted out of data collection
  Future<bool> isOptOut() => _posthog.isOptOut();

  /// Enable or disable verbose logs about the inner workings of the SDK.
  ///
  /// - [enabled] whether to enable or disable debug logs
  Future<void> debug(bool enabled) => _posthog.debug(enabled);

  /// Register a property to always be sent with all the following events until you call
  /// [unregister] with the same key.
  ///
  /// - [key] the Key
  /// - [value] the Value
  Future<void> register(String key, Object value) =>
      _posthog.register(key, value);

  /// Unregisters the previously set property to be sent with all the following events
  ///
  /// [key] the Key
  Future<void> unregister(String key) => _posthog.unregister(key);

  /// Returns if a feature flag is enabled via the native SDK.
  ///
  /// This is an async call that reads from the native iOS/Android SDK cache.
  /// For synchronous reads from the Dart-side cache, use [isFeatureEnabledSync].
  ///
  /// Docs https://posthog.com/docs/feature-flags and https://posthog.com/docs/experiments
  ///
  /// - [key] the Key of the feature
  Future<bool> isFeatureEnabled(String key) => _posthog.isFeatureEnabled(key);

  /// Reloads feature flags from both the native SDK and the Dart-side cache.
  ///
  /// After completion, both the native async methods and the Dart sync methods
  /// will reflect the updated flag values.
  Future<void> reloadFeatureFlags() => _posthog.reloadFeatureFlags();

  /// Creates a group.
  /// Docs https://posthog.com/docs/product-analytics/group-analytics
  ///
  /// - [groupType] the Group type
  /// - [groupKey] the Group key
  /// - [groupProperties] the Group properties, set as a "$group_set" property.
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

  /// Returns the feature flag value via the native SDK.
  ///
  /// This is an async call that reads from the native iOS/Android SDK cache.
  /// For synchronous reads from the Dart-side cache, use [getFeatureFlagSync].
  ///
  /// Returns `null` if the flag doesn't exist.
  /// For boolean flags, returns `true` or `false`.
  /// For multivariate flags, returns the variant string.
  Future<Object?> getFeatureFlag(String key) =>
      _posthog.getFeatureFlag(key: key);

  /// Returns the full feature flag result via the native SDK, including
  /// value and payload.
  ///
  /// This is an async call that reads from the native iOS/Android SDK cache.
  /// For synchronous reads from the Dart-side cache, use
  /// [getFeatureFlagResultSync].
  ///
  /// Returns `null` if the flag doesn't exist.
  ///
  /// Set [sendEvent] to `false` to suppress the `$feature_flag_called` event.
  /// This is useful when you only need the payload and don't want to emit the event.
  ///
  /// **Example:**
  /// ```dart
  /// final result = await Posthog().getFeatureFlagResult('my-flag');
  /// if (result != null && result.enabled) {
  ///   final variant = result.variant; // For multivariate flags
  ///   final payload = result.payload; // Associated payload data
  /// }
  /// ```
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult(String key,
          {bool sendEvent = true}) =>
      _posthog.getFeatureFlagResult(key: key, sendEvent: sendEvent);

  /// Returns the payload for a feature flag via the native SDK.
  @Deprecated(
      'Use getFeatureFlagResult instead, which returns both value and payload.')
  Future<Object?> getFeatureFlagPayload(String key) =>
      _posthog.getFeatureFlagPayload(key: key);

  // ---------------------------------------------------------------------------
  // Sync feature flag API — reads directly from Dart-side cache
  // ---------------------------------------------------------------------------

  /// Returns `true` if the feature flag is enabled, `false` otherwise.
  ///
  /// This is a **synchronous** read from the Dart-side cache — safe to call
  /// directly inside `build()` methods without `FutureBuilder`. Flags are
  /// loaded automatically during [setup] (when `preloadFeatureFlags: true`)
  /// and updated via [reloadFeatureFlags].
  ///
  /// See also [isFeatureEnabled] for the async native SDK equivalent.
  ///
  /// **Example:**
  /// ```dart
  /// if (Posthog().isFeatureEnabledSync('new-onboarding')) {
  ///   // Show new onboarding flow
  /// }
  /// ```
  bool isFeatureEnabledSync(String key) {
    final io = _posthog;
    if (io is PosthogFlutterIO) {
      return io.featureFlags?.isFeatureEnabled(key) ?? false;
    }
    return false;
  }

  /// Returns the feature flag value synchronously from the Dart-side cache.
  ///
  /// Safe to call directly inside `build()` methods.
  /// For boolean flags, returns `true` or `false`.
  /// For multivariate flags, returns the variant string.
  /// Returns `null` if the flag doesn't exist in the cache.
  ///
  /// See also [getFeatureFlag] for the async native SDK equivalent.
  Object? getFeatureFlagSync(String key) {
    final io = _posthog;
    if (io is PosthogFlutterIO) {
      return io.featureFlags?.getFeatureFlag(key);
    }
    return null;
  }

  /// Returns the full feature flag result synchronously from the Dart-side
  /// cache, including payload.
  ///
  /// Safe to call directly inside `build()` methods.
  /// Returns `null` if the flag doesn't exist in the cache.
  ///
  /// See also [getFeatureFlagResult] for the async native SDK equivalent.
  PostHogFeatureFlagResult? getFeatureFlagResultSync(String key) {
    final io = _posthog;
    if (io is PosthogFlutterIO) {
      return io.featureFlags?.getFeatureFlagResult(key);
    }
    return null;
  }

  /// Returns all currently cached feature flag results from the Dart-side cache.
  Map<String, PostHogFeatureFlagResult> getAllFeatureFlagResults() {
    final io = _posthog;
    if (io is PosthogFlutterIO) {
      return io.featureFlags?.getAllFlags() ?? {};
    }
    return {};
  }

  /// Returns whether the Dart-side feature flag cache has been loaded
  /// at least once.
  bool get isFeatureFlagsLoaded {
    final io = _posthog;
    if (io is PosthogFlutterIO) {
      return io.featureFlags?.isLoaded ?? false;
    }
    return false;
  }

  Future<void> flush() => _posthog.flush();

  /// Captures exceptions with optional custom properties
  ///
  /// - [error] - The error/exception to capture
  /// - [stackTrace] - Optional stack trace (if not provided, current stack trace will be used)
  /// - [properties] - Optional custom properties to attach to the exception event
  Future<void> captureException(
          {required Object error,
          StackTrace? stackTrace,
          Map<String, Object>? properties}) =>
      _posthog.captureException(
          error: error, stackTrace: stackTrace, properties: properties);

  /// Captures runZonedGuarded exceptions with optional custom properties
  /// https://api.flutter.dev/flutter/dart-async/runZonedGuarded.html
  ///
  /// - [error] - The error/exception to capture
  /// - [stackTrace] - Optional stack trace (if not provided, current stack trace will be used)
  /// - [properties] - Optional custom properties to attach to the exception event
  Future<void> captureRunZonedGuardedError(
      {required Object error,
      StackTrace? stackTrace,
      Map<String, Object>? properties}) async {
    final wrappedError = PostHogException(
        source: error, mechanism: 'runZonedGuarded', handled: false);
    await _posthog.captureException(
        error: wrappedError, stackTrace: stackTrace, properties: properties);
  }

  /// Closes the PostHog SDK and cleans up resources.
  ///
  /// Note: Please note that after calling close(), surveys will not be rendered until the SDK is re-initialized and the next navigation event occurs.
  Future<void> close() {
    _config = null;
    _currentScreen = null;
    PostHogInternalEvents.sessionRecordingActive.value = false;
    PosthogObserver.clearCurrentContext();

    // Uninstall Flutter integrations
    _uninstallFlutterIntegrations();

    return _posthog.close();
  }

  /// Returns the session Id if a session is active
  Future<String?> getSessionId() => _posthog.getSessionId();

  /// Starts session recording.
  ///
  /// This method will have no effect if PostHog is not enabled, or if session
  /// replay is disabled in your project settings.
  ///
  /// [resumeCurrent] - If true (default), resumes recording of the current session.
  /// If false, starts a new session and begins recording.
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    await _posthog.startSessionRecording(resumeCurrent: resumeCurrent);
    PostHogInternalEvents.sessionRecordingActive.value = true;
  }

  /// Stops the current session recording if one is in progress.
  ///
  /// This method will have no effect if PostHog is not enabled.
  Future<void> stopSessionRecording() async {
    await _posthog.stopSessionRecording();
    PostHogInternalEvents.sessionRecordingActive.value = false;
  }

  /// Returns whether session replay is currently active.
  Future<bool> isSessionReplayActive() => _posthog.isSessionReplayActive();

  Posthog._internal();
}
