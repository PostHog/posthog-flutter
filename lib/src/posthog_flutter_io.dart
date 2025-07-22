import 'dart:async';

import 'util/platform_io_stub.dart'
    if (dart.library.io) 'util/platform_io_real.dart';

import 'package:flutter/services.dart';

import 'package:posthog_flutter/src/surveys/survey_service.dart';
import 'package:posthog_flutter/src/util/logging.dart';
import 'surveys/models/posthog_display_survey.dart' as models;
import 'surveys/models/survey_callbacks.dart';

import 'posthog_config.dart';
import 'posthog_flutter_platform_interface.dart';

/// An implementation of [PosthogFlutterPlatformInterface] that uses method channels.
class PosthogFlutterIO extends PosthogFlutterPlatformInterface {
  PosthogFlutterIO() {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// The method channel used to interact with the native platform.
  final _methodChannel = const MethodChannel('posthog_flutter');

  /// Native plugin calls to Flutter
  ///
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'showSurvey':
        final Map<String, dynamic> survey =
            Map<String, dynamic>.from(call.arguments);
        return showSurvey(survey);
      case 'hideSurveys':
        await cleanupSurveys();
        return null;
      default:
        printIfDebug(
            '[PostHog] ${call.method} not implemented in PosthogFlutterPlatformInterface');
        return null;
    }
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    if (!isSupportedPlatform()) {
      printIfDebug('Cannot show survey: Platform is not supported');
      return;
    }

    final widget = PosthogFlutterPlatformInterface.instance;
    if (widget is! PosthogFlutterIO) {
      printIfDebug(
          'Cannot show survey: PosthogFlutterPlatformInterface instance is not PosthogFlutterIO');
      return;
    }

    final displaySurvey = models.PostHogDisplaySurvey.fromDict(survey);

    // Try to show using SurveyService
    // This will work if the user has set up the PosthogObserver correctly in their app
    await SurveyService().showSurvey(
      displaySurvey,
      (survey) async {
        // onShown
        try {
          await _methodChannel.invokeMethod('surveyAction', {'type': 'shown'});
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(shown): $exception');
        }
      },
      (survey, index, response) async {
        // onResponse
        int nextIndex = index;
        bool isSurveyCompleted = false;

        try {
          final result = await _methodChannel.invokeMethod('surveyAction', {
            'type': 'response',
            'index': index,
            'response': response,
          }) as Map;
          nextIndex = (result['nextIndex'] as num).toInt();
          isSurveyCompleted = result['isSurveyCompleted'] as bool;
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(response): $exception');
        }

        final nextQuestion = PostHogSurveyNextQuestion(
          questionIndex: nextIndex,
          isSurveyCompleted: isSurveyCompleted,
        );
        return nextQuestion;
      },
      (survey) async {
        // onClose
        try {
          await _methodChannel.invokeMethod('surveyAction', {'type': 'closed'});
        } on PlatformException catch (exception) {
          printIfDebug('Exception on surveyAction(closed): $exception');
        }
      },
    );
  }

  /// Cleans up any active surveys when the survey feature is stopped
  Future<void> cleanupSurveys() async {
    if (!isSupportedPlatform()) {
      printIfDebug('Cannot cleanup surveys: Platform is not supported');
      return;
    }

    SurveyService().hideSurvey();
  }

  /// Flutter to Native Calls
  ///
  @override
  Future<void> setup(PostHogConfig config) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('setup', config.toMap());
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on setup: $exception');
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('identify', {
        'userId': userId,
        if (userProperties != null) 'userProperties': userProperties,
        if (userPropertiesSetOnce != null)
          'userPropertiesSetOnce': userPropertiesSetOnce,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on identify: $exception');
    }
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('capture', {
        'eventName': eventName,
        if (properties != null) 'properties': properties,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on capture: $exception');
    }
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('screen', {
        'screenName': screenName,
        if (properties != null) 'properties': properties,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on screen: $exception');
    }
  }

  @override
  Future<void> alias({
    required String alias,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('alias', {
        'alias': alias,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on alias: $exception');
    }
  }

  @override
  Future<String> getDistinctId() async {
    if (!isSupportedPlatform()) {
      return "";
    }

    try {
      return await _methodChannel.invokeMethod('distinctId');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on getDistinctId: $exception');
      return "";
    }
  }

  @override
  Future<void> reset() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('reset');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on reset: $exception');
    }
  }

  @override
  Future<void> disable() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('disable');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on disable: $exception');
    }
  }

  @override
  Future<void> enable() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('enable');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on enable: $exception');
    }
  }

  @override
  Future<void> debug(bool enabled) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('debug', {
        'debug': enabled,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on debug: $exception');
    }
  }

  @override
  Future<bool> isFeatureEnabled(String key) async {
    if (!isSupportedPlatform()) {
      return false;
    }

    try {
      return await _methodChannel.invokeMethod('isFeatureEnabled', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on isFeatureEnabled: $exception');
      return false;
    }
  }

  @override
  Future<void> reloadFeatureFlags() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('reloadFeatureFlags');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on reloadFeatureFlags: $exception');
    }
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      await _methodChannel.invokeMethod('group', {
        'groupType': groupType,
        'groupKey': groupKey,
        if (groupProperties != null) 'groupProperties': groupProperties,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on group: $exception');
    }
  }

  @override
  Future<Object?> getFeatureFlag({
    required String key,
  }) async {
    if (!isSupportedPlatform()) {
      return null;
    }

    try {
      return await _methodChannel.invokeMethod('getFeatureFlag', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on getFeatureFlag: $exception');
      return null;
    }
  }

  @override
  Future<Object?> getFeatureFlagPayload({
    required String key,
  }) async {
    if (!isSupportedPlatform()) {
      return null;
    }

    try {
      return await _methodChannel.invokeMethod('getFeatureFlagPayload', {
        'key': key,
      });
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on getFeatureFlagPayload: $exception');
      return null;
    }
  }

  @override
  Future<void> register(String key, Object value) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel
          .invokeMethod('register', {'key': key, 'value': value});
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on register: $exception');
    }
  }

  @override
  Future<void> unregister(String key) async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel.invokeMethod('unregister', {'key': key});
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on unregister: $exception');
    }
  }

  @override
  Future<void> flush() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel.invokeMethod('flush');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on flush: $exception');
    }
  }

  @override
  Future<void> close() async {
    if (!isSupportedPlatform()) {
      return;
    }

    try {
      return await _methodChannel.invokeMethod('close');
    } on PlatformException catch (exception) {
      printIfDebug('Exeption on close: $exception');
    }
  }

  @override
  Future<String?> getSessionId() async {
    if (!isSupportedPlatform()) {
      return null;
    }

    try {
      final sessionId = await _methodChannel.invokeMethod('getSessionId');
      return sessionId;
    } on PlatformException catch (exception) {
      printIfDebug('Exception on getSessionId: $exception');
      return null;
    }
  }

  // For internal use
  @override
  Future<void> openUrl(String url) async {
    if (!isSupportedPlatform()) {
      printIfDebug('Cannot open url $url: Platform is not supported');
      return;
    }

    try {
      await _methodChannel.invokeMethod('openUrl', url);
    } on PlatformException catch (exception) {
      printIfDebug('Exception on openUrl: $exception');
    }
  }
}
