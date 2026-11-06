// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';
import 'package:posthog_flutter/src/util/logging.dart';
import 'package:posthog_flutter/src/utils/channel_serialization.dart';
import 'package:posthog_flutter/src/utils/property_normalizer.dart';

import 'src/feature_flag_result.dart';
import 'src/feature_flags_listeners.dart';
import 'src/feature_flags_loaded.dart';
import 'src/logs/posthog_log_severity.dart';
import 'src/posthog_config.dart';
import 'src/posthog_constants.dart';
import 'src/posthog_event.dart';
import 'src/posthog_flutter_platform_interface.dart';
import 'src/posthog_flutter_web_handler.dart';
import 'src/utils/before_send.dart';
import 'src/replay/web/web_canvas_mask_provider.dart';
import 'src/utils/capture_utils.dart';
import 'src/utils/event_options.dart';
import 'src/utils/feature_event.dart';

/// A web implementation of the PosthogFlutterPlatform of the PosthogFlutter plugin.
class PosthogFlutterWeb extends PosthogFlutterPlatformInterface {
  /// Constructs a PosthogFlutterWeb
  PosthogFlutterWeb();

  /// Stored configuration for accessing inAppIncludes and other settings
  PostHogConfig? _config;

  /// Copied at setup. Event beforeSend runs here, before posthog-js, the same
  /// way [PosthogFlutterIO] runs it before the platform channel.
  List<BeforeSendCallback> _beforeSendCallbacks = [];
  JSFunction? _featureFlagsUnsubscribe;

  // posthog-js has no $app_language. A registered super property would
  // persist across launches, be cleared by reset() and replace one the app
  // registered, so a before_send hook adds this to each event instead.
  String? _appLanguage;

  /// Bumped by each setup() and close(), so a posthog-js registration from an
  /// earlier one stops delivering even when it can't be unsubscribed.
  int _featureFlagsGeneration = 0;

  // posthog-js has no current screen, so the feature events get it from here
  // the way native SDKs stamp it: the last screen beforeSend accepted, under
  // its final name, until close().
  String? _currentScreen;

  PostHogEvent? _runBeforeSend(
    String eventName,
    Map<String, Object>? properties, {
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) {
    final distinctId =
        _beforeSendCallbacks.isEmpty ? null : currentWebDistinctId();
    final wasIdentified = distinctId != null && currentWebUserIdentified();
    final processed = applyBeforeSend(
      _beforeSendCallbacks,
      PostHogEvent(
        event: eventName,
        properties: properties,
        userProperties: userProperties,
        userPropertiesSetOnce: userPropertiesSetOnce,
        options: options == null ? null : {...options},
      ),
    );
    if (processed == null ||
        distinctId == null ||
        distinctId == currentWebDistinctId()) {
      return processed;
    }
    // posthog-js stores an event's `$set` as the current user's person
    // properties for flags, so after a reset() they would reach the next user.
    // identify() of an anonymous user links the two, so they stay.
    if (wasIdentified || !currentWebUserIdentified()) {
      processed
        ..userProperties = null
        ..userPropertiesSetOnce = null
        ..properties = {...?processed.properties}
        ..properties!.remove(r'$set')
        ..properties!.remove(r'$set_once');
    }
    // posthog-js builds the event only after the callbacks, so one calling
    // reset() or identify() would otherwise move the event to the new user.
    // Event properties win over the stored distinct id. A callback changing
    // consent under cookieless_mode swaps the id on purpose: neither the user
    // who opted out nor the shared cookieless id may come back.
    if (distinctId != r'$posthog_cookieless' &&
        !(posthog?.has_opted_out_capturing() ?? true)) {
      processed.properties = {
        'distinct_id': distinctId,
        ...?processed.properties,
      };
    }
    return processed;
  }

  /// posthog-js sends these calls' events without event properties, so
  /// options can't be attached.
  static void _logUnsupportedOptions(
    String method,
    Map<String, Object?>? options,
  ) {
    if (cleanEventOptions(options) == null) return;
    printIfDebug(
      '[PostHog] $method options are not supported on web and '
      'were dropped.',
    );
  }

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

    // If projectToken and host are in config, and posthog.init is to be handled by plugin:
    // This is an example if we wanted the plugin to also call posthog.init()
    // final jsOptions = <String, dynamic>{
    //   'api_host': config.host,
    //   // Add other relevant options from PostHogConfig if needed for JS init
    // }.jsify();
    // posthog?.callMethod('init'.toJS, config.projectToken.toJS, jsOptions);

    final ph = posthog;
    _config = config;
    _beforeSendCallbacks = config.beforeSend;

    // posthog-js is initialized by the host app, so a few config options never
    // reach it. Warn instead of silently ignoring them.
    if (!config.preloadFeatureFlags) {
      printIfDebug(
        'Warning: PostHogConfig.preloadFeatureFlags is not applied on Flutter web. '
        'posthog-js is initialized by your app, so set '
        'advanced_disable_feature_flags_on_first_load in your posthog.init({...}) call instead.',
      );
    }
    if (config.evaluationContexts?.isNotEmpty ?? false) {
      printIfDebug(
        'Warning: PostHogConfig.evaluationContexts is not applied on Flutter web. '
        'Set evaluation_contexts in your posthog.init({...}) call instead.',
      );
    }
    if (config.featureFlagRequestMaxRetries != 1) {
      printIfDebug(
        'Warning: PostHogConfig.featureFlagRequestMaxRetries is not applied on Flutter web. '
        'Set feature_flag_request_max_retries in your posthog.init({...}) call instead.',
      );
    }
    if (config.bootstrap != null) {
      printIfDebug(
        'Warning: PostHogConfig.bootstrap is not applied on Flutter web. '
        'Configure bootstrap in your posthog.init({...}) call instead.',
      );
    }

    WebCanvasMaskProvider(config).register();

    // Skipped for a posthog-js stub without onFeatureFlags.
    if (ph != null && (ph as JSObject).has('onFeatureFlags')) {
      // Repeated setup would otherwise deliver each load twice.
      _featureFlagsUnsubscribe?.callAsFunction();
      _featureFlagsUnsubscribe = null;
      final generation = ++_featureFlagsGeneration;

      // JS SDK calls with: (flags: string[], variants: Record, context?: {errorsLoading})
      final jsCallback =
          (JSArray jsFlags, JSObject jsFlagVariants, [JSObject? jsContext]) {
        // The posthog-js loader snippet queues the registration and returns
        // no unsubscribe, so a later setup() or close() can't remove it.
        if (generation != _featureFlagsGeneration) return;
        final loaded = featureFlagsLoadedFromMap({
          'variants': jsFlagVariants.dartify(),
          'errorsLoading': (jsContext?.dartify() as Map?)?['errorsLoading'],
        });
        FeatureFlagsListeners.instance.deliver(loaded);
      }.toJS;

      // posthog-js replays loaded flags synchronously, and a callback may call
      // close() or setup() before this returns the unsubscribe.
      final unsubscribe = ph.onFeatureFlags(jsCallback);
      if (generation == _featureFlagsGeneration) {
        _featureFlagsUnsubscribe = unsubscribe;
      } else {
        unsubscribe?.callAsFunction();
      }
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('identify', options);
    return handleWebMethodCall(
      MethodCall('identify', {
        'userId': userId,
        if (userProperties != null) 'userProperties': userProperties,
        if (userPropertiesSetOnce != null)
          'userPropertiesSetOnce': userPropertiesSetOnce,
      }),
    );
  }

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('setPersonProperties', options);
    if ((userPropertiesToSet?.isEmpty ?? true) &&
        (userPropertiesToSetOnce?.isEmpty ?? true)) {
      return;
    }

    return handleWebMethodCall(
      MethodCall('setPersonProperties', {
        if (userPropertiesToSet != null)
          'userPropertiesToSet': userPropertiesToSet,
        if (userPropertiesToSetOnce != null)
          'userPropertiesToSetOnce': userPropertiesToSetOnce,
      }),
    );
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    final processedEvent = _runBeforeSend(
      eventName,
      properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
      options: options,
    );
    if (processedEvent == null) {
      printIfDebug('[PostHog] Event dropped by beforeSend: $eventName');
      return;
    }

    return _sendCapture(processedEvent);
  }

  Future<void> _sendCapture(PostHogEvent processedEvent) {
    final extracted = CaptureUtils.extractUserProperties(
      properties: processedEvent.properties,
      userProperties: processedEvent.userProperties,
      userPropertiesSetOnce: processedEvent.userPropertiesSetOnce,
    );

    final extractedProperties = _withOptionProperties(
      extracted.properties,
      processedEvent.options,
      processedEvent.event,
    );
    final extractedUserProperties = extracted.userProperties;
    final extractedUserPropertiesSetOnce = extracted.userPropertiesSetOnce;

    final normalizedProperties = extractedProperties != null
        ? PropertyNormalizer.normalize(extractedProperties)
        : null;
    final normalizedUserProperties = extractedUserProperties != null
        ? PropertyNormalizer.normalize(extractedUserProperties)
        : null;
    final normalizedUserPropertiesSetOnce =
        extractedUserPropertiesSetOnce != null
            ? PropertyNormalizer.normalize(extractedUserPropertiesSetOnce)
            : null;

    return handleWebMethodCall(
      MethodCall('capture', {
        'eventName': processedEvent.event,
        if (normalizedProperties != null) 'properties': normalizedProperties,
        if (normalizedUserProperties != null)
          'userProperties': normalizedUserProperties,
        if (normalizedUserPropertiesSetOnce != null)
          'userPropertiesSetOnce': normalizedUserPropertiesSetOnce,
      }),
    );
  }

  /// posthog-js has no AI capture, so AI events are not sent on web.
  @override
  Future<String?> captureAi({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
    Map<String, Object?>? options,
  }) async {
    printIfDebug(
      '[PostHog] captureAi is not supported on web. '
      'The event "$eventName" was not sent.',
    );
    return null;
  }

  /// posthog-js has no options for these keys, so they are sent as their
  /// legacy properties, winning over a legacy property set on the event.
  static Map<String, Object>? _withOptionProperties(
    Map<String, Object>? properties,
    Map<String, Object?>? options,
    String eventName,
  ) {
    final optionProperties = eventOptionsToLegacyProperties(
      options,
      method: eventName,
    );
    if (optionProperties.isEmpty) return properties;
    return {...?properties, ...optionProperties};
  }

  @override
  Future<void> captureLog({
    required String body,
    PostHogLogSeverity level = PostHogLogSeverity.info,
    Map<String, Object>? attributes,
    String? traceId,
    String? spanId,
    int? traceFlags,
  }) async {
    final normalizedAttributes =
        attributes != null ? PropertyNormalizer.normalize(attributes) : null;

    return handleWebMethodCall(
      MethodCall('captureLog', {
        'body': body,
        'level': level.name,
        if (normalizedAttributes != null) 'attributes': normalizedAttributes,
        if (traceId != null) 'traceId': traceId,
        if (spanId != null) 'spanId': spanId,
        // traceFlags 0 is meaningful (W3C sampled-false); only omit when null.
        if (traceFlags != null) 'traceFlags': traceFlags,
      }),
    );
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
    Map<String, Object?>? options,
  }) async {
    // The screen name argument wins over a properties `$screen_name`.
    // beforeSend still runs after this and can change the name.
    final propsWithScreenName = <String, Object>{
      ...?properties,
      PostHogPropertyName.screenName: screenName,
    };

    final processedEvent = _runBeforeSend(
      PostHogEventName.screen,
      propsWithScreenName,
      options: options,
    );
    if (processedEvent == null) {
      printIfDebug('[PostHog] Screen event dropped by beforeSend: $screenName');
      return;
    }

    if (processedEvent.event != PostHogEventName.screen) {
      await _sendCapture(processedEvent);
      return;
    }

    final finalScreenName =
        processedEvent.properties?[PostHogPropertyName.screenName] as String? ??
            screenName;
    _currentScreen = finalScreenName;
    processedEvent.properties?.remove(PostHogPropertyName.screenName);
    final extracted = CaptureUtils.extractUserProperties(
      properties: processedEvent.properties,
      userProperties: processedEvent.userProperties,
      userPropertiesSetOnce: processedEvent.userPropertiesSetOnce,
    );
    final remaining = _withOptionProperties(
      extracted.properties,
      processedEvent.options,
      PostHogEventName.screen,
    );
    final userProperties = extracted.userProperties;
    final userPropertiesSetOnce = extracted.userPropertiesSetOnce;

    return handleWebMethodCall(
      MethodCall('screen', {
        'screenName': finalScreenName,
        if (remaining != null && remaining.isNotEmpty) 'properties': remaining,
        if (userProperties != null)
          'userProperties': PropertyNormalizer.normalize(userProperties),
        if (userPropertiesSetOnce != null)
          'userPropertiesSetOnce':
              PropertyNormalizer.normalize(userPropertiesSetOnce),
      }),
    );
  }

  @override
  Future<void> alias({
    required String alias,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('alias', options);
    return handleWebMethodCall(MethodCall('alias', {'alias': alias}));
  }

  @override
  Future<String> getDistinctId() async {
    final result = await handleWebMethodCall(const MethodCall('distinctId'));
    return result as String? ?? '';
  }

  @override
  Future<void> captureFeatureView({
    required String flag,
    String? flagVariant,
  }) =>
      _captureFeatureEvent(r'$feature_view', flag, flagVariant);

  @override
  Future<void> captureFeatureInteraction({
    required String flag,
    String? flagVariant,
  }) =>
      _captureFeatureEvent(r'$feature_interaction', flag, flagVariant);

  // Looks up the flag and starts the capture without an await in between, so
  // a reset() right after the call cannot move the event to the next user.
  Future<void> _captureFeatureEvent(
    String event,
    String flag,
    String? flagVariant,
  ) async {
    final screenName = _currentScreen;
    final result = flagVariant == null
        ? featureFlagResultFromMap(
            readFeatureFlagResult(flag, sendEvent: false),
            flag,
          )
        : null;
    final captured = featureEvent(
      event,
      flag,
      flagVariant ?? result?.variant ?? result?.enabled,
    );
    if (captured == null) return;
    await capture(
      eventName: event,
      properties: {
        ...captured.properties,
        if (screenName != null) PostHogPropertyName.screenName: screenName,
      },
      userProperties: captured.userProperties,
    );
  }

  @override
  Future<void> reset() async {
    return handleWebMethodCall(const MethodCall('reset'));
  }

  @override
  Future<void> optOut() async {
    return handleWebMethodCall(const MethodCall('disable'));
  }

  @override
  Future<void> optIn() async {
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
      MethodCall('register', {'key': key, 'value': value}),
    );
  }

  @override
  Future<void> unregister(String key) async {
    return handleWebMethodCall(MethodCall('unregister', {'key': key}));
  }

  @override
  Future<void> setAppLanguage(String? language) async {
    _appLanguage = language;
    if (language != null) _installAppLanguageHook();
  }

  static const _appLanguageHookMarker = '__posthogFlutterAppLanguage';
  static const _originalSetConfig = '__posthogFlutterOriginalSetConfig';

  // Runs first, like the native SDKs, so the app's before_send sees the value.
  // A registered or per-event $app_language is already on the event and wins.
  JSObject? _addAppLanguage(JSObject? event) {
    final language = _appLanguage;
    if (language == null) return event;
    try {
      final properties = event?.getProperty<JSAny?>('properties'.toJS);
      if (properties.isA<JSObject>() &&
          (properties as JSObject)
              .getProperty<JSAny?>(r'$app_language'.toJS)
              .isUndefinedOrNull &&
          !_excludesAppLanguage(event!, properties)) {
        properties.setProperty(r'$app_language'.toJS, language.toJS);
      }
    } catch (e) {
      printIfDebug('[PostHog] Failed to add \$app_language: $e');
    }
    return event;
  }

  // posthog-js applies property_denylist and strips minimal $feature_flag_called
  // events to an allowlist before before_send runs, so honor both here.
  bool _excludesAppLanguage(JSObject event, JSObject properties) {
    final ph = posthog as JSObject?;
    if (ph == null) return false;
    final config = ph.getProperty<JSAny?>('config'.toJS);
    if (config.isA<JSObject>()) {
      final denylist =
          (config as JSObject).getProperty<JSAny?>('property_denylist'.toJS);
      if (denylist.isA<JSArray>() &&
          (denylist as JSArray<JSAny?>)
              .toDart
              .any((p) => p.dartify() == r'$app_language')) {
        return true;
      }
    }
    return event.getProperty<JSAny?>('event'.toJS).dartify() ==
            r'$feature_flag_called' &&
        properties
                .getProperty<JSAny?>(r'$feature_flag_has_experiment'.toJS)
                .dartify() ==
            false &&
        ph.has('get_property') &&
        ph
                .callMethod<JSAny?>(
                    'get_property'.toJS, r'$minimal_flag_called_events'.toJS)
                .dartify() ==
            true;
  }

  late final JSFunction _appLanguageHook = _addAppLanguage.toJS
    ..setProperty(_appLanguageHookMarker.toJS, true.toJS);

  bool _isAppLanguageHook(JSAny? fn) =>
      fn.isA<JSFunction>() && (fn as JSObject).has(_appLanguageHookMarker);

  JSArray<JSAny?> _withAppLanguageHook(JSAny? hooks) => <JSAny?>[
        _appLanguageHook,
        if (hooks.isA<JSArray>())
          ...(hooks as JSArray<JSAny?>)
              .toDart
              .where((fn) => !_isAppLanguageHook(fn))
        else if (!hooks.isUndefinedOrNull && !_isAppLanguageHook(hooks))
          hooks,
      ].toJS;

  void _installAppLanguageHook() {
    final ph = posthog as JSObject?;
    if (ph == null || !ph.has('push')) return;
    // The loader snippet queues a pushed function until posthog.init() and
    // runs it before the queued method calls. A loaded posthog-js runs it now.
    // set_config is wrapped so a later before_send, queued or not, keeps the
    // hook first.
    final install = (JSObject instance) {
      final config = instance.getProperty<JSAny?>('config'.toJS);
      final setConfig = instance.getProperty<JSAny?>('set_config'.toJS);
      if (!config.isA<JSObject>() || !setConfig.isA<JSFunction>()) return;
      var original = setConfig as JSFunction;
      // Rewrapped each time, so a new plugin instance after a web hot restart
      // replaces the earlier one's wrapper.
      if (original.has(_originalSetConfig)) {
        original = original.getProperty<JSFunction>(_originalSetConfig.toJS);
      }
      final wrapped = ((JSAny? update) {
        if (update.isA<JSObject>() && (update as JSObject).has('before_send')) {
          // A copy, since the app's update may be frozen.
          update = globalContext
              .getProperty<JSObject>('Object'.toJS)
              .callMethod<JSObject>('assign'.toJS, JSObject(), update)
            ..setProperty('before_send'.toJS,
                _withAppLanguageHook(update.getProperty('before_send'.toJS)));
        }
        return original.callAsFunction(instance, update);
      }).toJS
        ..setProperty(_originalSetConfig.toJS, original);
      instance.setProperty('set_config'.toJS, wrapped);
      wrapped.callAsFunction(
        instance,
        JSObject()
          ..setProperty('before_send'.toJS,
              (config as JSObject).getProperty<JSAny?>('before_send'.toJS)),
      );
    }.toJSCaptureThis;
    try {
      ph.callMethod('push'.toJS, install);
    } catch (e) {
      printIfDebug('[PostHog] Failed to add the \$app_language hook: $e');
    }
  }

  @override
  Future<bool> isFeatureEnabled(
    String key, {
    bool? sendFeatureFlagEvent,
    bool? defaultValue,
  }) async {
    final result = await handleWebMethodCall(
      MethodCall('isFeatureEnabled', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
        if (defaultValue != null) 'defaultValue': defaultValue,
      }),
    );
    return result as bool? ?? false;
  }

  @override
  Future<PostHogFeatureFlagsLoaded> reloadFeatureFlags() async {
    return featureFlagsLoadedFromMap(
      await handleWebMethodCall(const MethodCall('reloadFeatureFlags')),
    );
  }

  @override
  Future<void> setPersonPropertiesForFlags(
    Map<String, Object> userProperties,
  ) async {
    return handleWebMethodCall(
      MethodCall('setPersonPropertiesForFlags', {
        'userProperties': userProperties,
      }),
    );
  }

  @override
  Future<void> resetPersonPropertiesForFlags() async {
    return handleWebMethodCall(
      const MethodCall('resetPersonPropertiesForFlags'),
    );
  }

  @override
  Future<void> setGroupPropertiesForFlags(
    String groupType,
    Map<String, Object> groupProperties,
  ) async {
    return handleWebMethodCall(
      MethodCall('setGroupPropertiesForFlags', {
        'groupType': groupType,
        'groupProperties': groupProperties,
      }),
    );
  }

  @override
  Future<void> resetGroupPropertiesForFlags({String? groupType}) async {
    return handleWebMethodCall(
      MethodCall('resetGroupPropertiesForFlags', {
        if (groupType != null) 'groupType': groupType,
      }),
    );
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
    Map<String, Object?>? options,
  }) async {
    _logUnsupportedOptions('group', options);
    return handleWebMethodCall(
      MethodCall('group', {
        'groupType': groupType,
        'groupKey': groupKey,
        if (groupProperties != null) 'groupProperties': groupProperties,
      }),
    );
  }

  @override
  Future<Object?> getFeatureFlag({
    required String key,
    bool? sendFeatureFlagEvent,
  }) async {
    return handleWebMethodCall(
      MethodCall('getFeatureFlag', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      }),
    );
  }

  @override
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool? sendFeatureFlagEvent,
  }) async {
    final result = await handleWebMethodCall(
      MethodCall('getFeatureFlagResult', {
        'key': key,
        if (sendFeatureFlagEvent != null) 'sendEvent': sendFeatureFlagEvent,
      }),
    );

    // Web SDK returns: { key, enabled, variant, payload }
    return featureFlagResultFromMap(result, key);
  }

  @override
  Future<List<PostHogFeatureFlagResult>?> getAllFeatureFlags() async {
    final results = await handleWebMethodCall(
      const MethodCall('getAllFeatureFlags'),
    );
    if (results is! List) return null;
    return results
        .map((result) => featureFlagResultFromMap(result, ''))
        .nonNulls
        .toList();
  }

  @override
  Future<void> flush() async {
    return handleWebMethodCall(const MethodCall('flush'));
  }

  @override
  Future<void> close() async {
    _currentScreen = null;
    _featureFlagsUnsubscribe?.callAsFunction();
    _featureFlagsUnsubscribe = null;
    _featureFlagsGeneration++;
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
  Future<void> registerPushNotificationToken(
    String deviceToken, {
    String? appId,
  }) async {
    // Not supported on web - posthog-js has no push subscription API
  }

  @override
  Future<void> unregisterPushNotificationToken() async {
    // Not supported on web - posthog-js has no push subscription API
  }

  @override
  Future<void> capturePushNotificationOpened({
    String? title,
    String? subtitle,
    String? body,
    Map<String, Object?>? payload,
    String? action,
  }) async {
    // Not supported on web - posthog-js has no push subscription API
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
    Map<String, Object?>? options,
  }) async {
    try {
      final exceptionData = DartExceptionProcessor.processException(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
        inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
        inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
        inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
      );

      final processedEvent = _runBeforeSend(
        PostHogEventName.exception,
        exceptionData.cast<String, Object>(),
        options: options,
      );
      if (processedEvent == null) {
        printIfDebug(
          '[PostHog] Exception event dropped by beforeSend: ${error.runtimeType}',
        );
        return;
      }

      if (processedEvent.event != PostHogEventName.exception) {
        await _sendCapture(processedEvent);
        return;
      }

      final extracted = CaptureUtils.extractUserProperties(
        properties: processedEvent.properties?.cast<String, Object>(),
        userProperties: processedEvent.userProperties,
        userPropertiesSetOnce: processedEvent.userPropertiesSetOnce,
      );
      final userProperties = extracted.userProperties;
      final userPropertiesSetOnce = extracted.userPropertiesSetOnce;
      // posthog-js's captureException takes no capture options, but capture
      // merges `$set` and `$set_once` from the event's properties.
      final normalizedData = PropertyNormalizer.normalize({
        ...?_withOptionProperties(
          extracted.properties,
          processedEvent.options,
          PostHogEventName.exception,
        ),
        if (userProperties != null) r'$set': userProperties,
        if (userPropertiesSetOnce != null) r'$set_once': userPropertiesSetOnce,
      });

      return await handleWebMethodCall(
        MethodCall('captureException', {'properties': normalizedData}),
      );
    } catch (error) {
      printIfDebug('Exception in captureException: $error');
    }
  }

  @override
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    return handleWebMethodCall(
      MethodCall('startSessionRecording', {'resumeCurrent': resumeCurrent}),
    );
  }

  @override
  Future<void> stopSessionRecording() async {
    return handleWebMethodCall(const MethodCall('stopSessionRecording'));
  }

  @override
  Future<bool> isSessionReplayActive() async {
    final result = await handleWebMethodCall(
      const MethodCall('isSessionReplayActive'),
    );
    return result as bool? ?? false;
  }

  @override
  Future<void> addExceptionStep(
    String message, {
    Map<String, Object>? properties,
  }) async {
    final normalizedProperties =
        properties != null ? PropertyNormalizer.normalize(properties) : null;

    return handleWebMethodCall(
      MethodCall('addExceptionStep', {
        'message': message,
        if (normalizedProperties != null) 'properties': normalizedProperties,
      }),
    );
  }
}
