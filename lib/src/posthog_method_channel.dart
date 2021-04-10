import 'package:flutter/services.dart';
import 'package:posthog_flutter/src/posthog_default_options.dart';
import 'package:posthog_flutter/src/posthog_platform_interface.dart';

const MethodChannel _channel = MethodChannel('posthogflutter');

class PosthogMethodChannel extends PosthogPlatform {
  Future<void> identify({
    required userId,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) async {
    try {
      await _channel.invokeMethod('identify', {
        'userId': userId,
        'properties': properties ?? {},
        'options': options ?? PosthogDefaultOptions.instance.options ?? {},
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> capture({
    required String eventName,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) async {
    try {
      await _channel.invokeMethod('capture', {
        'eventName': eventName,
        'properties': properties ?? {},
        'options': options ?? PosthogDefaultOptions.instance.options ?? {},
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> screen({
    required String screenName,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) async {
    try {
      await _channel.invokeMethod('screen', {
        'screenName': screenName,
        'properties': properties ?? {},
        'options': options ?? PosthogDefaultOptions.instance.options ?? {},
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> alias({
    required String alias,
    Map<String, dynamic>? options,
  }) async {
    try {
      await _channel.invokeMethod('alias', {
        'alias': alias,
        'options': options ?? PosthogDefaultOptions.instance.options ?? {},
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<String?> get getAnonymousId async {
    return await _channel.invokeMethod('getAnonymousId');
  }

  Future<void> reset() async {
    try {
      await _channel.invokeMethod('reset');
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> disable() async {
    try {
      await _channel.invokeMethod('disable');
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> enable() async {
    try {
      await _channel.invokeMethod('enable');
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> debug(bool enabled) async {
    try {
      await _channel.invokeMethod('debug', {
        'debug': enabled,
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }

  Future<void> setContext(Map<String, dynamic> context) async {
    try {
      await _channel.invokeMethod('setContext', {
        'context': context,
      });
    } on PlatformException catch (exception) {
      print(exception);
    }
  }
}
