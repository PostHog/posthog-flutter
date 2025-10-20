import 'package:meta/meta.dart';

import 'exceptions/posthog_error_tracking_autocapture_integration.dart';
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

    installFlutterIntegrations(config);

    return _posthog.setup(config);
  }

  void installFlutterIntegrations(PostHogConfig config) {
    // Install exception autocapture if enabled
    if (config.errorTrackingConfig.captureUnhandledExceptions) {
      PostHogErrorTrackingAutoCaptureIntegration.install(
        config: config.errorTrackingConfig,
        posthog: _posthog,
      );
    }
  }

  void uninstallFlutterIntegrations() {
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
    uninstallFlutterIntegrations();

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
  /// [handled] - Whether the exception was handled (true by default for manual captures)
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
    bool handled = true,
  }) =>
      _posthog.captureException(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
        handled: handled,
      );

  /// Closes the PostHog SDK and cleans up resources.
  ///
  /// Note: Please note that after calling close(), surveys will not be rendered until the SDK is re-initialized and the next navigation event occurs.
  Future<void> close() {
    _config = null;
    _currentScreen = null;
    PosthogObserver.clearCurrentContext();

    // Uninstall Flutter integrations
    uninstallFlutterIntegrations();

    return _posthog.close();
  }

  Future<String?> getSessionId() => _posthog.getSessionId();

  Posthog._internal();
}
