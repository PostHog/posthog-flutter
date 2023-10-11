import 'dart:io';

import 'package:posthog_flutter/src/posthog_platform_interface.dart';

export 'package:posthog_flutter/src/posthog_default_options.dart';
export 'package:posthog_flutter/src/posthog_observer.dart';

class Posthog {
  static PosthogPlatform get _posthog => PosthogPlatform.instance;

  static final Posthog _instance = Posthog._internal();

  factory Posthog() {
    return _instance;
  }

  String? currentScreen;

  Future<void> identify({
    required String userId,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) {
    return _posthog.identify(
      userId: userId,
      properties: properties,
      options: options,
    );
  }

  Future<void> capture({
    required String eventName,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) {
    if (properties != null &&
        !properties.containsKey('\$screen_name') &&
        this.currentScreen != null) {
      properties['\$screen_name'] = this.currentScreen;
    }
    return _posthog.capture(
      eventName: eventName,
      properties: properties,
      options: options,
    );
  }

  Future<void> screen({
    required String screenName,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? options,
  }) {
    if (screenName != '/') {
      this.currentScreen = screenName;
    }
    return _posthog.screen(
      screenName: screenName,
      properties: properties,
      options: options,
    );
  }

  Future<void> alias({
    required String alias,
    Map<String, dynamic>? options,
  }) {
    return _posthog.alias(
      alias: alias,
      options: options,
    );
  }

  Future<String?> get getAnonymousId {
    return _posthog.getAnonymousId;
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
    if (Platform.isAndroid) {
      throw Exception('Debug flag cannot be dynamically set on Android.\n'
          'Add to AndroidManifest and avoid calling this method when Platform.isAndroid.');
    }

    return _posthog.debug(enabled);
  }

  Future<void> setContext(Map<String, dynamic> context) {
    return _posthog.setContext(context);
  }

  Future<bool?> isFeatureEnabled(String key) {
    return _posthog.isFeatureEnabled(key);
  }

  Future<void> reloadFeatureFlags() {
    return _posthog.reloadFeatureFlags();
  }

  Future<void> group({
    required String groupType,
    required String groupKey,
    required Map<String, dynamic> groupProperties,
  }) {
    return _posthog.group(
        groupType: groupType,
        groupKey: groupKey,
        groupProperties: groupProperties);
  }

  Future<void> flush() {
    return _posthog.flush();
  }

  Posthog._internal();
}
