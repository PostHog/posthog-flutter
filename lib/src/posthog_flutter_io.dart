import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'posthog_flutter_platform_interface.dart';

/// An implementation of [PosthogFlutterPlatformInterface] that uses method channels.
class PosthogFlutterIO extends PosthogFlutterPlatformInterface {
  /// The method channel used to interact with the native platform.
  final _methodChannel = const MethodChannel('posthog_flutter');

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    try {
      await _methodChannel.invokeMethod('identify', {
        'userId': userId,
        if (userProperties != null) 'userProperties': userProperties,
        if (userPropertiesSetOnce != null)
          'userPropertiesSetOnce': userPropertiesSetOnce,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on identify: $exception');
    }
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
  }) async {
    try {
      await _methodChannel.invokeMethod('capture', {
        'eventName': eventName,
        if (properties != null) 'properties': properties,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on capture: $exception');
    }
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    try {
      await _methodChannel.invokeMethod('screen', {
        'screenName': screenName,
        if (properties != null) 'properties': properties,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on screen: $exception');
    }
  }

  @override
  Future<void> alias({
    required String alias,
  }) async {
    try {
      await _methodChannel.invokeMethod('alias', {
        'alias': alias,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on alias: $exception');
    }
  }

  @override
  Future<String> getDistinctId() async {
    try {
      return await _methodChannel.invokeMethod('distinctId');
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on getDistinctId: $exception');
      return "";
    }
  }

  @override
  Future<void> reset() async {
    try {
      await _methodChannel.invokeMethod('reset');
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on reset: $exception');
    }
  }

  @override
  Future<void> disable() async {
    try {
      await _methodChannel.invokeMethod('disable');
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on disable: $exception');
    }
  }

  @override
  Future<void> enable() async {
    try {
      await _methodChannel.invokeMethod('enable');
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on enable: $exception');
    }
  }

  @override
  Future<void> debug(bool enabled) async {
    try {
      await _methodChannel.invokeMethod('debug', {
        'debug': enabled,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on debug: $exception');
    }
  }

  @override
  Future<bool> isFeatureEnabled(String key) async {
    try {
      return await _methodChannel.invokeMethod('isFeatureEnabled', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on isFeatureEnabled: $exception');
      return false;
    }
  }

  @override
  Future<void> reloadFeatureFlags() async {
    try {
      await _methodChannel.invokeMethod('reloadFeatureFlags');
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on reloadFeatureFlags: $exception');
    }
  }

  @override
  Future<void> awaitFeatureFlagsLoaded() async {
    try {
      await _methodChannel.invokeMethod('awaitFeatureFlagsLoaded');
    } on PlatformException catch (exception) {
      _printIfDebug('Exception on awaitFeatureFlagsLoaded: $exception');
    }
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {
    try {
      await _methodChannel.invokeMethod('group', {
        'groupType': groupType,
        'groupKey': groupKey,
        if (groupProperties != null) 'groupProperties': groupProperties,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on group: $exception');
    }
  }

  @override
  Future<Object?> getFeatureFlag({
    required String key,
  }) async {
    try {
      return await _methodChannel.invokeMethod('getFeatureFlag', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on getFeatureFlag: $exception');
      return null;
    }
  }

  @override
  Future<Object?> getFeatureFlagPayload({
    required String key,
  }) async {
    try {
      return await _methodChannel.invokeMethod('getFeatureFlagPayload', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on getFeatureFlagPayload: $exception');
      return null;
    }
  }

  @override
  Future<void> register(String key, Object value) async {
    try {
      return await _methodChannel
          .invokeMethod('register', {'key': key, 'value': value});
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on register: $exception');
    }
  }

  @override
  Future<void> unregister(String key) async {
    try {
      return await _methodChannel.invokeMethod('unregister', {'key': key});
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on unregister: $exception');
    }
  }

  @override
  Future<void> flush() async {
    try {
      return await _methodChannel.invokeMethod('flush');
    } on PlatformException catch (exception) {
      _printIfDebug('Exeption on flush: $exception');
    }
  }

  void _printIfDebug(String message) {
    if (kDebugMode) {
      print(message);
    }
  }
}
