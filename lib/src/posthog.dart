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

  /// Android and iOS only
  /// Only used for the manual setup
  /// Requires disabling the automatic init on Android and iOS:
  /// com.posthog.posthog.AUTO_INIT: false
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

  /// Sets a callback to be invoked when feature flags are loaded from the PostHog server.
  ///
  /// The behavior of this callback differs slightly between platforms:
  ///
  /// **Web:**
  /// The callback will receive:
  /// - `flags`: A list of active feature flag keys (List<String>).
  /// - `flagVariants`: A map of feature flag keys to their variant values (Map<String, dynamic>).
  ///
  /// **Mobile (Android/iOS):**
  /// The callback serves primarily as a notification that the native PostHog SDK
  /// has finished loading feature flags. In this case:
  /// - `flags`: Will be an empty list.
  /// - `flagVariants`: Will be an empty map.
  /// After this callback is invoked, you can reliably use `Posthog().getFeatureFlag('your-flag-key')`
  /// or `Posthog().isFeatureEnabled('your-flag-key')` to get the values of specific flags.
  ///
  /// **Common Parameters:**
  /// - `errorsLoading` (optional named parameter): A boolean indicating if an error occurred during the request to load the feature flags.
  ///   This is `true` if the request timed out or if there was an error. It will be `false` if the request was successful.
  ///
  /// This is particularly useful on the first app load to ensure flags are available before you try to access them.
  ///
  /// Example:
  /// ```dart
  /// Posthog().onFeatureFlags((flags, flagVariants, {errorsLoading}) {
  ///   if (errorsLoading == true) {
  ///     // Handle error, e.g. flags might be stale or unavailable
  ///     print('Error loading feature flags!');
  ///     return;
  ///   }
  ///   // On Web, you can iterate through flags and flagVariants directly.
  ///   // On Mobile, flags and flagVariants will be empty here.
  ///   // After this callback, you can safely query specific flags:
  ///   final isNewFeatureEnabled = await Posthog().isFeatureEnabled('new-feature');
  ///   if (isNewFeatureEnabled) {
  ///     // Implement logic for 'new-feature'
  ///   }
  ///   final variantValue = await Posthog().getFeatureFlag('multivariate-flag');
  ///   if (variantValue == 'test-variant') {
  ///     // Implement logic for 'test-variant' of 'multivariate-flag'
  ///   }
  /// });
  /// ```
  void onFeatureFlags(OnFeatureFlagsCallback callback) =>
      _posthog.onFeatureFlags(callback);

  Posthog._internal();
}
