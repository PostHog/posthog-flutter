import 'dart:io';

import 'package:meta/meta.dart';
import 'package:posthog_flutter/src/posthog_platform_interface.dart';

export 'package:posthog_flutter/src/posthog_observer.dart';
export 'package:posthog_flutter/src/posthog_default_options.dart';

class Posthog {
  static PosthogPlatform get _posthog => PosthogPlatform.instance;

  static Future<void> identify({
    @required userId,
    Map<String, dynamic> traits,
    Map<String, dynamic> options,
  }) {
    return _posthog.identify(
      userId: userId,
      traits: traits,
      options: options,
    );
  }

  static Future<void> track({
    @required String eventName,
    Map<String, dynamic> properties,
    Map<String, dynamic> options,
  }) {
    return _posthog.track(
      eventName: eventName,
      properties: properties,
      options: options,
    );
  }

  static Future<void> screen({
    @required String screenName,
    Map<String, dynamic> properties,
    Map<String, dynamic> options,
  }) {
    return _posthog.screen(
      screenName: screenName,
      properties: properties,
      options: options,
    );
  }

  static Future<void> group({
    @required String groupId,
    Map<String, dynamic> traits,
    Map<String, dynamic> options,
  }) {
    return _posthog.group(
      groupId: groupId,
      traits: traits,
      options: options,
    );
  }

  static Future<void> alias({
    @required String alias,
    Map<String, dynamic> options,
  }) {
    return _posthog.alias(
      alias: alias,
      options: options,
    );
  }

  static Future<String> get getAnonymousId {
    return _posthog.getAnonymousId;
  }

  static Future<void> reset() {
    return _posthog.reset();
  }

  static Future<void> disable() {
    return _posthog.disable();
  }

  static Future<void> enable() {
    return _posthog.enable();
  }

  static Future<void> debug(bool enabled) {
    if (Platform.isAndroid) {
      throw Exception('Debug flag cannot be dynamically set on Android.\n'
          'Add to AndroidManifest and avoid calling this method when Platform.isAndroid.');
    }

    return _posthog.debug(enabled);
  }

  static Future<void> setContext(Map<String, dynamic> context) {
    return _posthog.setContext(context);
  }
}
