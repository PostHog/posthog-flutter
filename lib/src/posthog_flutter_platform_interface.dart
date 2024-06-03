import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'posthog_flutter_io.dart';

abstract class PosthogFlutterPlatformInterface extends PlatformInterface {
  /// Constructs a PosthogFlutterPlatform.
  PosthogFlutterPlatformInterface() : super(token: _token);

  static final Object _token = Object();

  static PosthogFlutterPlatformInterface _instance = PosthogFlutterIO();

  /// The default instance of [PosthogFlutterPlatformInterface] to use.
  ///
  /// Defaults to [PosthogFlutterIO].
  static PosthogFlutterPlatformInterface get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PosthogFlutterPlatformInterface] when
  /// they register themselves.
  static set instance(PosthogFlutterPlatformInterface instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> identify(
      {required String userId,
      Map<String, Object>? userProperties,
      Map<String, Object>? userPropertiesSetOnce}) {
    throw UnimplementedError('identify() has not been implemented.');
  }

  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
  }) {
    throw UnimplementedError('capture() has not been implemented.');
  }

  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) {
    throw UnimplementedError('screen() has not been implemented.');
  }

  Future<void> alias({
    required String alias,
  }) {
    throw UnimplementedError('alias() has not been implemented.');
  }

  Future<String> getDistinctId() {
    throw UnimplementedError('getDistinctId() has not been implemented.');
  }

  Future<void> reset() {
    throw UnimplementedError('reset() has not been implemented.');
  }

  Future<void> disable() {
    throw UnimplementedError('disable() has not been implemented.');
  }

  Future<void> enable() {
    throw UnimplementedError('enable() has not been implemented.');
  }

  Future<void> debug(bool enabled) {
    throw UnimplementedError('debug() has not been implemented.');
  }

  Future<void> register(String key, Object value) {
    throw UnimplementedError('register() has not been implemented.');
  }

  Future<void> unregister(String key) {
    throw UnimplementedError('unregister() has not been implemented.');
  }

  Future<bool> isFeatureEnabled(String key) {
    throw UnimplementedError('isFeatureEnabled() has not been implemented.');
  }

  Future<void> reloadFeatureFlags() {
    throw UnimplementedError('reloadFeatureFlags() has not been implemented.');
  }

  /// Returns a Future, that completes only once the Feature Flags are loaded
  Future<void> awaitFeatureFlagsLoaded() {
    throw UnimplementedError('awaitFeatureFlagsLoaded() has not been implemented.');
  }

  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) {
    throw UnimplementedError('group() has not been implemented.');
  }

  Future<Object?> getFeatureFlag({
    required String key,
  }) {
    throw UnimplementedError('getFeatureFlag() has not been implemented.');
  }

  Future<Object?> getFeatureFlagPayload({
    required String key,
  }) {
    throw UnimplementedError(
        'getFeatureFlagPayload() has not been implemented.');
  }

  Future<void> flush() {
    throw UnimplementedError('flush() has not been implemented.');
  }

  // TODO: missing capture with more parameters, close
}
