import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/posthog_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPosthogFlutterPlatform
    with MockPlatformInterfaceMixin
    implements PosthogFlutterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<void> alias({required String alias}) {
    // TODO: implement alias
    throw UnimplementedError();
  }

  @override
  Future<void> capture(
      {required String eventName, Map<String, dynamic>? properties}) {
    // TODO: implement capture
    throw UnimplementedError();
  }

  @override
  Future<void> debug(bool enabled) {
    // TODO: implement debug
    throw UnimplementedError();
  }

  @override
  Future<void> disable() {
    // TODO: implement disable
    throw UnimplementedError();
  }

  @override
  Future<void> enable() {
    // TODO: implement enable
    throw UnimplementedError();
  }

  @override
  // TODO: implement getDistinctId
  Future<String?> get getDistinctId => throw UnimplementedError();

  @override
  Future getFeatureFlag({required String key}) {
    // TODO: implement getFeatureFlag
    throw UnimplementedError();
  }

  @override
  Future<Map?> getFeatureFlagAndPayload({required String key}) {
    // TODO: implement getFeatureFlagAndPayload
    throw UnimplementedError();
  }

  @override
  Future<Map?> getFeatureFlagPayload({required String key}) {
    // TODO: implement getFeatureFlagPayload
    throw UnimplementedError();
  }

  @override
  Future<void> group(
      {required String groupType,
      required String groupKey,
      Map<String, dynamic>? groupProperties}) {
    // TODO: implement group
    throw UnimplementedError();
  }

  @override
  Future<void> identify(
      {required String userId, Map<String, dynamic>? properties}) {
    // TODO: implement identify
    throw UnimplementedError();
  }

  @override
  Future<bool?> isFeatureEnabled(String key) {
    // TODO: implement isFeatureEnabled
    throw UnimplementedError();
  }

  @override
  Future<void> reloadFeatureFlags() {
    // TODO: implement reloadFeatureFlags
    throw UnimplementedError();
  }

  @override
  Future<void> reset() {
    // TODO: implement reset
    throw UnimplementedError();
  }

  @override
  Future<void> screen(
      {required String screenName, Map<String, dynamic>? properties}) {
    // TODO: implement screen
    throw UnimplementedError();
  }

  @override
  Future<void> register(String key, dynamic value) {
    // TODO: implement register
    throw UnimplementedError();
  }
}

void main() {
  final PosthogFlutterPlatform initialPlatform =
      PosthogFlutterPlatform.instance;

  test('$MethodChannelPosthogFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelPosthogFlutter>());
  });

  test('getPlatformVersion', () async {
    Posthog posthogFlutterPlugin = Posthog();
    MockPosthogFlutterPlatform fakePlatform = MockPosthogFlutterPlatform();
    PosthogFlutterPlatform.instance = fakePlatform;

    expect(await posthogFlutterPlugin.getPlatformVersion(), '42');
  });
}
