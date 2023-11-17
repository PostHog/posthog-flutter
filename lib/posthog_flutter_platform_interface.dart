import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'posthog_flutter_method_channel.dart';

abstract class PosthogFlutterPlatform extends PlatformInterface {
  /// Constructs a PosthogFlutterPlatform.
  PosthogFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static PosthogFlutterPlatform _instance = MethodChannelPosthogFlutter();

  /// The default instance of [PosthogFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelPosthogFlutter].
  static PosthogFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PosthogFlutterPlatform] when
  /// they register themselves.
  static set instance(PosthogFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> identify(
      {required String userId, Map<String, dynamic>? properties}) {
    throw UnimplementedError('identify() has not been implemented.');
  }

  Future<void> capture({
    required String eventName,
    Map<String, dynamic>? properties,
  }) {
    throw UnimplementedError('capture() has not been implemented.');
  }

  Future<void> screen({
    required String screenName,
    Map<String, dynamic>? properties,
  }) {
    throw UnimplementedError('screen() has not been implemented.');
  }

  Future<void> alias({
    required String alias,
  }) {
    throw UnimplementedError('alias() has not been implemented.');
  }

  Future<String?> get getDistinctId {
    throw UnimplementedError('getAnonymousId() has not been implemented.');
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

  Future<void> register(String key, dynamic value) {
    throw UnimplementedError('register() has not been implemented.');
  }

  Future<bool?> isFeatureEnabled(String key) {
    throw UnimplementedError('isFeatureEnabled() has not been implemented.');
  }

  Future<void> reloadFeatureFlags() {
    throw UnimplementedError('reloadFeatureFlags() has not been implemented.');
  }

  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, dynamic>? groupProperties,
  }) {
    throw UnimplementedError('group() has not been implemented.');
  }

  Future<dynamic> getFeatureFlag({
    required String key,
  }) {
    throw UnimplementedError('getFeatureFlag() has not been implemented.');
  }

  Future<Map?> getFeatureFlagPayload({
    required String key,
  }) {
    throw UnimplementedError(
        'getFeatureFlagPayload() has not been implemented.');
  }

  Future<Map?> getFeatureFlagAndPayload({
    required String key,
  }) {
    throw UnimplementedError(
        'getFeatureFlagAndPayload() has not been implemented.');
  }
}
