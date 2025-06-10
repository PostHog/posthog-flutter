import 'package:meta/meta.dart';

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
  /// **Behavior of `onFeatureFlags` callback (when provided in `PostHogConfig`):**
  ///
  /// **Web:**
  /// The callback will receive:
  /// - `flags`: A list of active feature flag keys (List<String>).
  /// - `flagVariants`: A map of feature flag keys to their variant values (Map<String, dynamic>).
  /// - `errorsLoading`: Will be `false` as the callback firing implies success.
  ///
  /// **Mobile (Android/iOS):**
  /// The callback serves primarily as a notification that the native PostHog SDK
  /// has finished loading feature flags. In this case:
  /// - `flags`: Will be an empty list.
  /// - `flagVariants`: Will be an empty map.
  /// - `errorsLoading`: Will be `null` if the native call was successful but contained no error info, or `true` if an error occurred during Dart-side processing of the callback.
  /// After this callback is invoked, you can reliably use `Posthog().getFeatureFlag('your-flag-key')`
  /// or `Posthog().isFeatureEnabled('your-flag-key')` to get the values of specific flags.
  ///
  /// **Example with `onFeatureFlags` in `PostHogConfig`:**
  /// ```dart
  /// final config = PostHogConfig(
  ///   apiKey: 'YOUR_API_KEY',
  ///   host: 'YOUR_POSTHOG_HOST',
  ///   onFeatureFlags: (flags, flagVariants, {errorsLoading}) {
  ///     if (errorsLoading == true) {
  ///       print('Error loading feature flags!');
  ///       return;
  ///     }
  ///     // ... process flags ...
  ///   },
  /// );
  /// await Posthog().setup(config);
  /// ```
  ///
  /// For Android and iOS, if you are performing a manual setup,
  /// ensure `com.posthog.posthog.AUTO_INIT: false` is set in your native configuration.
  Future<void> setup(PostHogConfig config) {
    _config = config; // Store the config
    return _posthog.setup(config);
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

  Future<void> disable() => _posthog.disable();

  Future<void> enable() => _posthog.enable();

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

  Future<void> close() {
    _config = null;
    _currentScreen = null;
    return _posthog.close();
  }

  Future<String?> getSessionId() => _posthog.getSessionId();

  Posthog._internal();
}
