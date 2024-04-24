import 'posthog_flutter_platform_interface.dart';

class Posthog {
  static PosthogFlutterPlatformInterface get _posthog =>
      PosthogFlutterPlatformInterface.instance;

  static final _instance = Posthog._internal();

  factory Posthog() {
    return _instance;
  }

  String? _currentScreen;

  Future<void> configure({
    required String apiKey,
    required String host,
    bool debug = false,
    bool trackApplicationLifecycleEvents = false,
  }) {
    return _posthog.configure(apiKey, host,
        debug: debug,
        trackApplicationLifecycleEvents: trackApplicationLifecycleEvents);
  }

  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) {
    return _posthog.identify(
        userId: userId,
        userProperties: userProperties,
        userPropertiesSetOnce: userPropertiesSetOnce);
  }

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
  }) {
    return _posthog.alias(
      alias: alias,
    );
  }

  Future<String> getDistinctId() {
    return _posthog.getDistinctId();
  }

  Future<void> reset() {
    return _posthog.reset();
  }

  Future<void> disable() {
    return _posthog.disable();
  }

  Future<void> enable() {
    return _posthog.enable();
  }

  Future<void> debug(bool enabled) {
    return _posthog.debug(enabled);
  }

  Future<void> register(String key, Object value) {
    return _posthog.register(key, value);
  }

  Future<void> unregister(String key) {
    return _posthog.unregister(key);
  }

  Future<bool> isFeatureEnabled(String key) {
    return _posthog.isFeatureEnabled(key);
  }

  Future<void> reloadFeatureFlags() {
    return _posthog.reloadFeatureFlags();
  }

  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) {
    return _posthog.group(
      groupType: groupType,
      groupKey: groupKey,
      groupProperties: groupProperties,
    );
  }

  Future<Object?> getFeatureFlag(String key) {
    return _posthog.getFeatureFlag(key: key);
  }

  Future<Object?> getFeatureFlagPayload(String key) {
    return _posthog.getFeatureFlagPayload(key: key);
  }

  Future<void> flush() async {
    return _posthog.flush();
  }

  Posthog._internal();
}
