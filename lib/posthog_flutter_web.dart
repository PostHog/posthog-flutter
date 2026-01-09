// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/posthog_config.dart';
import 'src/posthog_flutter_platform_interface.dart';
import 'src/posthog_flutter_web_handler.dart';

/// A web implementation of the PosthogFlutterPlatform of the PosthogFlutter plugin.
class PosthogFlutterWeb extends PosthogFlutterPlatformInterface {
  /// Constructs a PosthogFlutterWeb
  PosthogFlutterWeb();

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'posthog_flutter',
      const StandardMethodCodec(),
      registrar,
    );
    final instance = PosthogFlutterWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);

    // Set the platform instance so that Posthog() can call methods directly
    // on the web implementation instead of going through the method channel.
    // This is required because method channels can only pass serializable data,
    // not function callbacks like onFeatureFlags.
    PosthogFlutterPlatformInterface.instance = instance;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    // The 'setup' call is now handled by the setup method override.
    // Other method calls are delegated to handleWebMethodCall.
    if (call.method == 'setup') {
      // This case should ideally not be hit if Posthog().setup directly calls the overridden setup.
      // However, to be safe, we can log or ignore.
      // For now, let's assume direct call to overridden setup handles it.
      return null;
    }
    return handleWebMethodCall(call);
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    // It's assumed posthog-js is initialized by the user in their HTML.
    // This setup primarily hooks into the existing posthog-js instance.

    // If apiKey and host are in config, and posthog.init is to be handled by plugin:
    // This is an example if we wanted the plugin to also call posthog.init()
    // final jsOptions = <String, dynamic>{
    //   'api_host': config.host,
    //   // Add other relevant options from PostHogConfig if needed for JS init
    // }.jsify();
    // posthog?.callMethod('init'.toJS, config.apiKey.toJS, jsOptions);

    final ph = posthog;
    if (config.onFeatureFlags != null && ph != null) {
      final dartCallback = config.onFeatureFlags!;

      // JS SDK calls with: (flags: string[], variants: Record, context?: {errorsLoading})
      // We ignore the JS parameters and just invoke the void callback
      final jsCallback =
          (JSArray jsFlags, JSObject jsFlagVariants, [JSObject? jsContext]) {
        dartCallback();
      }.toJS;

      ph.onFeatureFlags(jsCallback);
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    return handleWebMethodCall(MethodCall('identify', {
      'userId': userId,
      if (userProperties != null) 'userProperties': userProperties,
      if (userPropertiesSetOnce != null)
        'userPropertiesSetOnce': userPropertiesSetOnce,
    }));
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? groups,
  }) async {
    Map<String, Object>? mergedProperties =
        properties == null ? null : {...properties};

    if (groups != null && groups.isNotEmpty) {
      mergedProperties ??= <String, Object>{};
      final existingGroups = mergedProperties['\$groups'];
      if (existingGroups is Map) {
        mergedProperties['\$groups'] = {
          ...Map<String, Object>.from(
            existingGroups.map(
              (key, value) => MapEntry(key.toString(), value as Object),
            ),
          ),
          ...groups,
        };
      } else {
        mergedProperties['\$groups'] = groups;
      }
    }

    return handleWebMethodCall(MethodCall('capture', {
      'eventName': eventName,
      if (mergedProperties != null) 'properties': mergedProperties,
    }));
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    return handleWebMethodCall(MethodCall('screen', {
      'screenName': screenName,
      if (properties != null) 'properties': properties,
    }));
  }

  @override
  Future<void> alias({required String alias}) async {
    return handleWebMethodCall(MethodCall('alias', {'alias': alias}));
  }

  @override
  Future<String> getDistinctId() async {
    final result = await handleWebMethodCall(const MethodCall('distinctId'));
    return result as String? ?? '';
  }

  @override
  Future<void> reset() async {
    return handleWebMethodCall(const MethodCall('reset'));
  }

  @override
  Future<void> disable() async {
    return handleWebMethodCall(const MethodCall('disable'));
  }

  @override
  Future<void> enable() async {
    return handleWebMethodCall(const MethodCall('enable'));
  }

  @override
  Future<bool> isOptOut() async {
    final result = await handleWebMethodCall(const MethodCall('isOptOut'));
    return result as bool? ?? true;
  }

  @override
  Future<void> debug(bool enabled) async {
    return handleWebMethodCall(MethodCall('debug', {'debug': enabled}));
  }

  @override
  Future<void> register(String key, Object value) async {
    return handleWebMethodCall(
        MethodCall('register', {'key': key, 'value': value}));
  }

  @override
  Future<void> unregister(String key) async {
    return handleWebMethodCall(MethodCall('unregister', {'key': key}));
  }

  @override
  Future<bool> isFeatureEnabled(String key) async {
    final result =
        await handleWebMethodCall(MethodCall('isFeatureEnabled', {'key': key}));
    return result as bool? ?? false;
  }

  @override
  Future<void> reloadFeatureFlags() async {
    return handleWebMethodCall(const MethodCall('reloadFeatureFlags'));
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {
    return handleWebMethodCall(MethodCall('group', {
      'groupType': groupType,
      'groupKey': groupKey,
      if (groupProperties != null) 'groupProperties': groupProperties,
    }));
  }

  @override
  Future<Object?> getFeatureFlag({required String key}) async {
    return handleWebMethodCall(MethodCall('getFeatureFlag', {'key': key}));
  }

  @override
  Future<Object?> getFeatureFlagPayload({required String key}) async {
    return handleWebMethodCall(
        MethodCall('getFeatureFlagPayload', {'key': key}));
  }

  @override
  Future<void> flush() async {
    return handleWebMethodCall(const MethodCall('flush'));
  }

  @override
  Future<void> close() async {
    return handleWebMethodCall(const MethodCall('close'));
  }

  @override
  Future<String?> getSessionId() async {
    final result = await handleWebMethodCall(const MethodCall('getSessionId'));
    return result as String?;
  }

  @override
  Future<void> openUrl(String url) async {
    // Not supported on web
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    // Not supported on web - surveys handled by posthog-js
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {
    // Not implemented on web
  }
}
