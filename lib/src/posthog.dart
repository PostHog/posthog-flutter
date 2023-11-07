import 'dart:io';

import 'package:posthog_flutter/posthog_flutter_platform_interface.dart';
export 'package:posthog_flutter/src/posthog_observer.dart';

class Posthog {
  static PosthogFlutterPlatform get _posthog => PosthogFlutterPlatform.instance;

  static final Posthog _instance = Posthog._internal();

  factory Posthog() {
    return _instance;
  }

  String? currentScreen;

  Future<String?> getPlatformVersion() {
    return PosthogFlutterPlatform.instance.getPlatformVersion();
  }

  Future<void> identify({
    required String userId,
    Map<String, dynamic>? properties,
  }) {
    return _posthog.identify(userId: userId, properties: properties);
  }

  Future<void> capture({
    required String eventName,
    Map<String, dynamic>? properties,
  }) {
    if (properties != null &&
        !properties.containsKey('\$screen_name') &&
        this.currentScreen != null) {
      properties['\$screen_name'] = this.currentScreen;
    }
    return _posthog.capture(
      eventName: eventName,
      properties: properties,
    );
  }

  Future<void> screen({
    required String screenName,
    Map<String, dynamic>? properties,
  }) {
    if (screenName != '/') {
      this.currentScreen = screenName;
    }
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

  Future<String?> get getAnonymousId {
    return _posthog.getDistinctId;
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

  // Future<void> setContext(Map<String, dynamic> context) {
  //   return _posthog.setContext(context);
  // }

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
      groupProperties: groupProperties,
    );
  }

  Future<dynamic> getFeatureFlag(String key) {
    return _posthog.getFeatureFlag(key: key);
  }

  Future<Map?> getFeatureFlagPayload(String key) {
    return _posthog.getFeatureFlagPayload(key: key);
  }

  Future<Map> getFeatureFlagAndPayload(String key) {
    return _posthog.getFeatureFlagAndPayload(key: key);
  }

  Posthog._internal();
}
