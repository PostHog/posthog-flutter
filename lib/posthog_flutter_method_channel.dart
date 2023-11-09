import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'posthog_flutter_platform_interface.dart';
import 'src/models/feature_flag_data.dart';

/// An implementation of [PosthogFlutterPlatform] that uses method channels.
class MethodChannelPosthogFlutter extends PosthogFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('posthog_flutter');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  Future<void> identify({
    required String userId,
    Map<String, dynamic>? properties,
  }) async {
    try {
      await methodChannel.invokeMethod('identify', {
        'userId': userId,
        'properties': properties ?? {},
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> capture({
    required String eventName,
    Map<String, dynamic>? properties,
  }) async {
    try {
      await methodChannel.invokeMethod(
          'capture', {'eventName': eventName, 'properties': properties ?? {}});
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> screen({
    required String screenName,
    Map<String, dynamic>? properties,
  }) async {
    try {
      await methodChannel.invokeMethod('screen', {
        'screenName': screenName,
        'properties': properties ?? {},
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> alias({
    required String alias,
  }) async {
    try {
      await methodChannel.invokeMethod('alias', {
        'alias': alias,
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<String?> get getDistinctId async {
    return await methodChannel.invokeMethod('getDistinctId');
  }

  Future<void> reset() async {
    try {
      await methodChannel.invokeMethod('reset');
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> disable() async {
    try {
      await methodChannel.invokeMethod('disable');
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> enable() async {
    try {
      await methodChannel.invokeMethod('enable');
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> debug(bool enabled) async {
    try {
      await methodChannel.invokeMethod('debug', {
        'debug': enabled,
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<bool?> isFeatureEnabled(String key) async {
    try {
      return await methodChannel.invokeMethod('isFeatureEnabled', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      print(exception);
      return null;
    }
  }

  @override
  Future<void> reloadFeatureFlags() async {
    try {
      await methodChannel.invokeMethod('reloadFeatureFlags');
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, dynamic>? groupProperties,
  }) async {
    try {
      await methodChannel.invokeMethod('group', {
        'groupType': groupType,
        'groupKey': groupKey,
        'groupProperties': groupProperties ?? {},
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  @override
  Future<dynamic> getFeatureFlag({
    required String key,
  }) async {
    try {
      return await methodChannel.invokeMethod('getFeatureFlag', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      print(exception);
      return null;
    }
  }

  @override
  Future<Map?> getFeatureFlagPayload({
    required String key,
  }) async {
    try {
      return await methodChannel.invokeMethod('getFeatureFlagPayload', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      print(exception);
      return {};
    }
  }

  @override
  Future<FeatureFlagData?> getFeatureFlagAndPayload({
    required String key,
  }) async {
    try {
      final Map<String, dynamic>? result =
          await methodChannel.invokeMethod('getFeatureFlagAndPayload', {
        'key': key,
      });

      if (result != null) {
        return FeatureFlagData.fromMap(result);
      }

      return null;
    } on PlatformException catch (exception) {
      if (kDebugMode) {
        print('Exeption on getFeatureFlagAndPayload(): $exception');
      }
      rethrow;
    }
  }

  Future<void> register(String key, dynamic value) async {
    try {
      return await methodChannel
          .invokeMethod('register', {'key': key, 'value': value});
    } on PlatformException catch (exception) {
      print(exception);
    }
  }
}
