import 'package:meta/meta.dart';

import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'posthog_config.dart';
import 'posthog_flutter_platform_interface.dart';
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
  /// await Posthog().setup(config);
  /// ```
  ///
  /// For Android and iOS, if you are performing a manual setup,
  /// ensure `com.posthog.posthog.AUTO_INIT: false` is set in your native configuration.
  Future<void> setup(PostHogConfig config) {
    _config = config; // Store the config

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

  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) =>
      _posthog.identify(
          userId: userId,
          userProperties: userProperties,
          userPropertiesSetOnce: userPropertiesSetOnce);

  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    /// Event-level group context.
    ///
    /// This associates *only this event* with the provided groups, without
    /// persisting the group mapping for future events (unlike `group()`).
    ///
    /// On iOS/Android, this is passed to the native SDK's `groups` parameter
    /// which properly merges with any sticky groups set via `group()`.
    Map<String, Object>? groups,
  }) {
    final propertiesCopy = properties == null ? null : {...properties};

    final currentScreen = _currentScreen;
    if (currentScreen != null) {
      final props = propertiesCopy ?? <String, Object>{};
      if (!props.containsKey('\$screen_name')) {
        props['\$screen_name'] = currentScreen;
      }
      return _posthog.capture(
        eventName: eventName,
        properties: props,
        groups: groups,
      );
    }

    return _posthog.capture(
      eventName: eventName,
      properties: propertiesCopy,
      groups: groups,
    );
  }

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

  Future<void> alias({
    required String alias,
  }) =>
      _posthog.alias(
        alias: alias,
      );

  Future<String> getDistinctId() => _posthog.getDistinctId();

  Future<void> reset() => _posthog.reset();

  Future<void> disable() {
    // Uninstall Flutter-specific integrations when disabling
    _uninstallFlutterIntegrations();

    return _posthog.disable();
  }

  Future<void> enable() => _posthog.enable();

  Future<bool> isOptOut() => _posthog.isOptOut();

  Future<void> debug(bool enabled) => _posthog.debug(enabled);

  Future<void> register(String key, Object value) =>
      _posthog.register(key, value);

  Future<void> unregister(String key) => _posthog.unregister(key);

  Future<bool> isFeatureEnabled(String key) => _posthog.isFeatureEnabled(key);

  Future<void> reloadFeatureFlags() => _posthog.reloadFeatureFlags();

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

  Future<Object?> getFeatureFlag(String key) =>
      _posthog.getFeatureFlag(key: key);

  Future<Object?> getFeatureFlagPayload(String key) =>
      _posthog.getFeatureFlagPayload(key: key);

  Future<void> flush() => _posthog.flush();

  /// Captures exceptions with optional custom properties
  ///
  /// [error] - The error/exception to capture
  /// [stackTrace] - Optional stack trace (if not provided, current stack trace will be used)
  /// [properties] - Optional custom properties to attach to the exception event
  Future<void> captureException(
          {required Object error,
          StackTrace? stackTrace,
          Map<String, Object>? properties}) =>
      _posthog.captureException(
          error: error, stackTrace: stackTrace, properties: properties);

  /// Closes the PostHog SDK and cleans up resources.
  ///
  /// Note: Please note that after calling close(), surveys will not be rendered until the SDK is re-initialized and the next navigation event occurs.
  Future<void> close() {
    _config = null;
    _currentScreen = null;
    PosthogObserver.clearCurrentContext();

    // Uninstall Flutter integrations
    _uninstallFlutterIntegrations();

    return _posthog.close();
  }

  Future<String?> getSessionId() => _posthog.getSessionId();

  Posthog._internal();
}
