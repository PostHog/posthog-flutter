import 'package:posthog_flutter/src/posthog_method_channel.dart';

abstract class PosthogPlatform {
  /// The default instance of [PosthogPlatform] to use
  ///
  /// Platform-specific plugins should override this with their own
  /// platform-specific class that extends [PosthogPlatform] when they
  /// register themselves.
  ///
  /// Defaults to [PosthogMethodChannel]
  static PosthogPlatform instance = PosthogMethodChannel();

  Future<void> identify({
    required userId,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) {
    throw UnimplementedError('identify() has not been implemented.');
  }

  Future<void> capture({
    required String eventName,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) {
    throw UnimplementedError('capture() has not been implemented.');
  }

  Future<void> screen({
    required String screenName,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) {
    throw UnimplementedError('screen() has not been implemented.');
  }

  Future<void> alias({
    required String alias,
    Map<String, dynamic>? options,
  }) {
    throw UnimplementedError('alias() has not been implemented.');
  }

  Future<String?> get getAnonymousId {
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

  Future<void> setContext(Map<String, dynamic> context) {
    throw UnimplementedError('setContext() has not been implemented.');
  }
}
