import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/file_storage.dart';
import 'error_tracking/dart_exception_processor.dart';
import 'feature_flag_result.dart';
import 'logs/posthog_log_severity.dart';
import 'posthog_config.dart';
import 'posthog_constants.dart';
import 'posthog_desktop_app_info.dart';
import 'posthog_desktop_client.dart';
import 'posthog_desktop_context.dart';
import 'posthog_desktop_exception_steps.dart';
import 'posthog_desktop_lifecycle.dart';
import 'posthog_desktop_storage.dart';
import 'posthog_event.dart';
import 'posthog_flutter_platform_interface.dart';
import 'util/logging.dart';
import 'utils/before_send.dart';
import 'utils/capture_utils.dart';
import 'utils/property_normalizer.dart';

/// The Windows and Linux implementation, built on the pure-Dart
/// [DesktopPostHog] client.
///
/// Every method is wrapped in a guard: an error inside the SDK is logged in
/// debug builds and never thrown into the app. Calls made before setup() or
/// after close() are ignored, with a debug warning.
class PosthogFlutterDesktop extends PosthogFlutterPlatformInterface {
  /// Creates the implementation for an app that keeps its state in
  /// [appDirectory], whose build recorded [appInfo], and that runs in the
  /// IANA time zone [timezone].
  PosthogFlutterDesktop({
    required String appDirectory,
    required DesktopAppInfo appInfo,
    required String? timezone,
  })  : _appDirectory = appDirectory,
        _appInfo = appInfo,
        _timezone = timezone;

  /// See [DesktopStorage.appDirectory].
  final String _appDirectory;

  final DesktopAppInfo _appInfo;

  final String? _timezone;

  DesktopPostHog? _client;

  /// The configuration of the latest setup(), read by the Dart-side hooks:
  /// beforeSend, onFeatureFlags and exception processing.
  PostHogConfig? _config;

  void Function()? _featureFlagsUnsubscribe;

  /// Null while exception steps are disabled or no client is set up.
  ExceptionStepsBuffer? _exceptionSteps;

  DesktopAppLifecycle? _appLifecycle;

  /// The client that [op] goes to. There is none before setup() and after
  /// close(), and the call is then dropped.
  DesktopPostHog? _clientFor(String op) {
    final client = _client;
    if (client == null) {
      printIfDebug('[PostHog] $op ignored: PostHog is not set up or was '
          'closed.');
    }
    return client;
  }

  Future<void> _guard(
    String op,
    FutureOr<void> Function(DesktopPostHog client) fn,
  ) =>
      _guardWith<void>(op, null, fn);

  /// Runs [op] on the client, or returns [fallback] when there is no client
  /// or the SDK fails.
  Future<T> _guardWith<T>(
    String op,
    T fallback,
    FutureOr<T> Function(DesktopPostHog client) fn,
  ) async {
    try {
      final client = _clientFor(op);
      return client == null ? fallback : await fn(client);
    } catch (e) {
      printIfDebug('[PostHog] Exception on $op: $e');
      return fallback;
    }
  }

  @override
  Future<void> setup(PostHogConfig config) async {
    try {
      _setup(config);
    } catch (e) {
      printIfDebug('[PostHog] Exception on setup: $e');
    }
  }

  void _setup(PostHogConfig config) {
    // The Dart-side hooks follow every setup(), while a running client keeps
    // its configuration until close().
    _config = config;
    if (_client != null) {
      printIfDebug('[PostHog] Setup called despite already being setup!');
      return;
    }
    // Created synchronously, so calls made right after an unawaited setup()
    // already reach the client.
    _startClient(config);
  }

  void _startClient(PostHogConfig config) {
    final storageDirectory =
        DesktopStorage.projectDirectory(_appDirectory, config.projectToken);
    final client = DesktopPostHog(
      config,
      staticContext: collectDesktopContext(_appInfo),
      timezone: _timezone,
      storage: FileStorage(storageDirectory),
    );
    _client = client;
    _featureFlagsUnsubscribe =
        client.onFeatureFlags(() => _config?.onFeatureFlags?.call());

    final stepsConfig = config.errorTrackingConfig.exceptionSteps;
    _exceptionSteps = stepsConfig.enabled
        ? ExceptionStepsBuffer(maxBytes: stepsConfig.maxBytes)
        : null;

    final appLifecycle = _appLifecycle = DesktopAppLifecycle(
      binding: _widgetsBinding(),
      storageDirectory: storageDirectory,
      version: _appInfo.version,
      build: _appInfo.build,
      captureEvents: config.captureApplicationLifecycleEvents,
      // Straight to the client: lifecycle events do not pass through the
      // beforeSend callbacks, as PostHogConfig.beforeSend documents.
      capture: (event, properties) =>
          client.capture(event, properties: properties),
      flush: client.flush,
    );
    // While opted out, enable() starts it. An app set up after its window
    // became active has missed that activation, so it is reported as opened.
    if (!client.optedOut) appLifecycle.start(captureOpenedIfActive: true);
  }

  static WidgetsBinding? _widgetsBinding() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      printIfDebug(
        '[PostHog] Call WidgetsFlutterBinding.ensureInitialized() before '
        'setup() to capture Application Opened and Backgrounded events.',
      );
      return null;
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) =>
      _guard('identify', (client) {
        client.identify(
          userId,
          userProperties: _normalize(userProperties),
          userPropertiesSetOnce: _normalize(userPropertiesSetOnce),
        );
      });

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
  }) =>
      _guard('setPersonProperties', (client) {
        client.setPersonProperties(
          userPropertiesToSet: _normalize(userPropertiesToSet),
          userPropertiesToSetOnce: _normalize(userPropertiesToSetOnce),
        );
      });

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) =>
      _guard('capture', (_) async {
        if (!_hasName(eventName)) return;

        final processed = await _runBeforeSend(
          eventName,
          properties,
          userProperties: userProperties,
          userPropertiesSetOnce: userPropertiesSetOnce,
        );
        if (processed == null) {
          printIfDebug('[PostHog] Event dropped by beforeSend: $eventName');
          return;
        }
        // A callback may have renamed the event.
        if (!_hasName(processed.event)) return;

        // Resolved after the callbacks, which may be async: a client closed
        // meanwhile must not write to the on-disk state again.
        final client = _clientFor('capture');
        if (client == null) return;
        client.capture(
          processed.event,
          properties: _withExceptionSteps(
            processed.event,
            _mergeUserProps(
              processed.properties,
              processed.userProperties,
              processed.userPropertiesSetOnce,
            ),
          ),
        );
      });

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) =>
      _guard('screen', (client) async {
        // Opted out, nothing happens: no callback runs, and the screen does
        // not become the current one.
        if (client.optedOut) return;

        final processed = await _runBeforeSend(
          PostHogEventName.screen,
          <String, Object>{
            ...?properties,
            PostHogPropertyName.screenName: screenName,
          },
        );
        if (processed == null) {
          printIfDebug(
              '[PostHog] Screen event dropped by beforeSend: $screenName');
          return;
        }

        // A renamed event is no longer a screen view, so it is captured as a
        // regular event.
        if (processed.event != PostHogEventName.screen) {
          await capture(
            eventName: processed.event,
            properties: processed.properties,
          );
          return;
        }

        // Re-added after the callbacks, so one that rebuilds the property map
        // cannot drop the screen name.
        final finalScreenName =
            processed.properties?[PostHogPropertyName.screenName] as String? ??
                screenName;
        if (finalScreenName.isEmpty) {
          printIfDebug('[PostHog] Screen event dropped: empty screen name');
          return;
        }

        // Resolved again after the callbacks, as in capture().
        final current = _clientFor('screen');
        if (current == null) return;
        // Later events that set no `$screen_name` of their own carry this one.
        current.registerForSession(
            {PostHogPropertyName.screenName: finalScreenName});
        current.capture(
          PostHogEventName.screen,
          properties: <String, Object?>{
            ...?_normalize(processed.properties),
            PostHogPropertyName.screenName: finalScreenName,
          },
        );
      });

  /// Structured logs are not supported on the desktop implementation.
  @override
  Future<void> captureLog({
    required String body,
    PostHogLogSeverity level = PostHogLogSeverity.info,
    Map<String, Object>? attributes,
    String? traceId,
    String? spanId,
    int? traceFlags,
  }) async {}

  @override
  Future<void> registerPushNotificationToken(
    String deviceToken, {
    String? appId,
  }) async {
    // Push notifications are not supported on desktop.
  }

  @override
  Future<void> unregisterPushNotificationToken() async {
    // Push notifications are not supported on desktop.
  }

  @override
  Future<void> capturePushNotificationOpened({
    String? title,
    String? subtitle,
    String? body,
    Map<String, Object?>? payload,
    String? action,
  }) async {
    // Push notifications are not supported on desktop.
  }

  @override
  Future<void> alias({required String alias}) =>
      _guard('alias', (client) => client.alias(alias));

  @override
  Future<String> getDistinctId() =>
      _guardWith('getDistinctId', '', (client) => client.getDistinctId());

  @override
  Future<void> reset() => _guard('reset', (client) => client.reset());

  @override
  Future<void> disable() => _guard('disable', (client) {
        client.optOut();
        _appLifecycle?.stop();
      });

  @override
  Future<void> enable() => _guard('enable', (client) {
        client.optIn();
        // Opting in is not an app open: an active app is reported as opened
        // on its next activation.
        _appLifecycle?.start();
      });

  /// Reports opted out without a client: before setup() and after close().
  @override
  Future<bool> isOptOut() =>
      _guardWith('isOptOut', true, (client) => client.optedOut);

  @override
  Future<void> debug(bool enabled) =>
      _guard('debug', (client) => client.debug(enabled));

  @override
  Future<void> register(String key, Object value) => _guard('register',
      (client) => client.register(PropertyNormalizer.normalize({key: value})));

  @override
  Future<void> unregister(String key) =>
      _guard('unregister', (client) => client.unregister(key));

  @override
  Future<bool> isFeatureEnabled(String key) => _guardWith('isFeatureEnabled',
      false, (client) => client.isFeatureEnabled(key) ?? false);

  @override
  Future<void> reloadFeatureFlags() => _guard(
      'reloadFeatureFlags', (client) => client.reloadFeatureFlagsAsync());

  @override
  Future<void> setPersonPropertiesForFlags(
    Map<String, Object> userProperties,
  ) =>
      _guard('setPersonPropertiesForFlags', (client) {
        client.setPersonPropertiesForFlags(
          _normalize(userProperties) ?? const {},
        );
      });

  @override
  Future<void> resetPersonPropertiesForFlags() => _guard(
      'resetPersonPropertiesForFlags',
      (client) => client.resetPersonPropertiesForFlags());

  @override
  Future<void> setGroupPropertiesForFlags(
    String groupType,
    Map<String, Object> groupProperties,
  ) =>
      _guard('setGroupPropertiesForFlags', (client) {
        final normalized = _normalize(groupProperties) ?? const {};
        client.setGroupPropertiesForFlags({groupType: normalized});
      });

  @override
  Future<void> resetGroupPropertiesForFlags({String? groupType}) => _guard(
      'resetGroupPropertiesForFlags',
      (client) => client.resetGroupPropertiesForFlags(groupType: groupType));

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) =>
      _guard('group', (client) {
        client.group(
          groupType,
          groupKey,
          groupProperties: _normalize(groupProperties),
        );
      });

  @override
  Future<Object?> getFeatureFlag({required String key}) => _guardWith<Object?>(
      'getFeatureFlag', null, (client) => client.getFeatureFlag(key));

  @override
  Future<Object?> getFeatureFlagPayload({required String key}) => _guardWith(
      'getFeatureFlagPayload',
      null,
      (client) => client.getFeatureFlagResult(key, sendEvent: false)?.payload);

  @override
  Future<PostHogFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool sendEvent = true,
  }) =>
      _guardWith('getFeatureFlagResult', null,
          (client) => client.getFeatureFlagResult(key, sendEvent: sendEvent));

  @override
  Future<void> flush() => _guard('flush', (client) => client.flush());

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) =>
      _guard('captureException', (_) async {
        final exceptionProps = DartExceptionProcessor.processException(
          error: error,
          stackTrace: stackTrace,
          properties: properties,
          inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
          inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
          inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
        );

        final processed = await _runBeforeSend(
          PostHogEventName.exception,
          exceptionProps.cast<String, Object>(),
        );
        if (processed == null) {
          printIfDebug(
            '[PostHog] Exception event dropped by beforeSend: ${error.runtimeType}',
          );
          return;
        }

        // A renamed event is no longer an exception, so it is captured as a
        // regular event.
        if (processed.event != PostHogEventName.exception) {
          await capture(
            eventName: processed.event,
            properties: processed.properties,
          );
          return;
        }

        final client = _clientFor('captureException');
        if (client == null) return;
        client.capture(
          PostHogEventName.exception,
          properties: _withExceptionSteps(
            PostHogEventName.exception,
            _normalize(processed.properties),
          ),
        );
      });

  @override
  Future<void> addExceptionStep(
    String message, {
    Map<String, Object>? properties,
  }) =>
      _guard('addExceptionStep', (client) {
        // Nothing is recorded while opted out: the steps would reach an
        // exception captured after opting in.
        if (client.optedOut) return;
        _exceptionSteps?.add(message, properties: properties);
      });

  @override
  Future<void> close() => _guard('close', (client) {
        _client = null;
        _exceptionSteps = null;
        _appLifecycle?.dispose();
        _appLifecycle = null;
        _featureFlagsUnsubscribe?.call();
        _featureFlagsUnsubscribe = null;

        // Nothing is sent on close: queued events stay on disk and go out
        // with the next client.
        client.close();
      });

  @override
  Future<String?> getSessionId() =>
      _guardWith('getSessionId', null, (client) => client.getSessionId());

  @override
  Future<void> openUrl(String url) async {
    // Surveys/native UI only - not supported on desktop.
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    // Surveys are not supported on desktop.
  }

  @override
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    // Session replay is not supported on desktop.
  }

  @override
  Future<void> stopSessionRecording() async {
    // Session replay is not supported on desktop.
  }

  @override
  Future<bool> isSessionReplayActive() async => false;

  /// Applies the beforeSend callbacks to an event in order. Running them here
  /// rather than in the client keeps SDK-internal events ($identify,
  /// $feature_flag_called, ...) and the properties the SDK adds out of the
  /// callbacks' sight.
  ///
  /// Returns the possibly modified event, or null if any callback drops it
  /// or throws.
  Future<PostHogEvent?> _runBeforeSend(
    String eventName,
    Map<String, Object>? properties, {
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    var event = PostHogEvent(
      event: eventName,
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );

    final callbacks = _config?.beforeSend ?? const <BeforeSendCallback>[];
    for (final callback in callbacks) {
      try {
        final result = await runBeforeSend<PostHogEvent>(callback, event);
        if (result == null) return null;
        event = result;
      } catch (e) {
        // A callback that fails may be the one scrubbing sensitive data, so
        // neither the original nor a partially processed event is sent.
        printIfDebug(
          '[PostHog] Warning: beforeSend callback threw an exception; dropping event: $e',
        );
        return null;
      }
    }
    return event;
  }

  /// Whether [event] has a name; an event without one is dropped.
  static bool _hasName(String event) {
    if (event.isNotEmpty) return true;
    printIfDebug('[PostHog] Event dropped: empty event name');
    return false;
  }

  /// Adds the recorded exception steps to an `$exception` event that does not
  /// set its own.
  Map<String, Object?>? _withExceptionSteps(
    String event,
    Map<String, Object?>? properties,
  ) {
    final steps = _exceptionSteps?.steps;
    if (event != PostHogEventName.exception || steps == null || steps.isEmpty) {
      return properties;
    }
    return {r'$exception_steps': steps, ...?properties};
  }

  Map<String, Object?>? _mergeUserProps(
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  ) {
    // Inline $set/$set_once in properties are legacy but still honored, with
    // the explicit parameters winning per key.
    final extracted = CaptureUtils.extractUserProperties(
      properties: properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );

    final set = _normalize(extracted.userProperties);
    final setOnce = _normalize(extracted.userPropertiesSetOnce);
    final merged = <String, Object?>{
      ...?_normalize(extracted.properties),
      if (set != null && set.isNotEmpty) r'$set': set,
      if (setOnce != null && setOnce.isNotEmpty) r'$set_once': setOnce,
    };
    return merged.isNotEmpty ? merged : null;
  }

  /// Converts the values jsonEncode cannot handle, which storage and /batch/
  /// payloads need.
  Map<String, Object>? _normalize(Map<String, Object>? properties) {
    if (properties == null || properties.isEmpty) return properties;
    return Map<String, Object>.from(PropertyNormalizer.normalize(properties));
  }
}
