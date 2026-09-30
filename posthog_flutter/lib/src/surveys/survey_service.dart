import 'dart:async';

import 'package:flutter/material.dart';

import '../util/logging.dart';
import '../posthog_observer.dart';
import 'models/posthog_display_survey.dart';
import 'models/survey_callbacks.dart';
import 'models/survey_appearance.dart';
import 'widgets/survey_bottom_sheet.dart';

/// How long to wait before showing a survey.
///
/// [seconds] comes from the survey's `surveyPopupDelaySeconds`. Null, zero,
/// and negative values show the survey immediately, matching iOS and Android.
Duration surveyPopupDelay(double? seconds) {
  if (seconds == null || seconds.isNaN || seconds.isInfinite || seconds <= 0) {
    return Duration.zero;
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

/// A service that manages displaying surveys
///
/// This service uses the PosthogObserver to access the current navigation context
/// for displaying surveys. Users must add PosthogObserver to their navigatorObservers list.
class SurveyService {
  static final SurveyService _instance = SurveyService._internal();

  factory SurveyService() => _instance;

  SurveyService._internal();

  bool _isShowingSurvey = false;
  bool _isDismissingSurvey = false;
  bool _dismissSurveyWhenReady = false;
  Route<dynamic>? _currentSurveyRoute;
  PostHogDisplaySurvey? _currentSurvey;
  Completer<void>? _programmaticDismissal;
  Timer? _popupDelayTimer;
  Completer<void>? _popupDelayGate;
  int _popupDelayGeneration = 0;
  PostHogDisplaySurvey? _pendingSurvey;
  OnSurveyClosed? _pendingOnClosed;

  /// Shows a survey using the PosthogObserver context
  Future<void> showSurvey(
    PostHogDisplaySurvey survey,
    OnSurveyShown onShown,
    OnSurveyResponse onResponse,
    OnSurveyClosed onClosed,
  ) async {
    if (_isShowingSurvey) {
      printIfDebug('[PostHog] A survey is already being displayed');
      return;
    }

    // A survey still waiting out its delay has not been shown. Replacing it
    // closes that presentation the same way the iOS surveys delegate does.
    _cancelPendingSurvey();

    final delay = surveyPopupDelay(survey.appearance?.surveyPopupDelaySeconds);
    if (delay > Duration.zero) {
      final generation = ++_popupDelayGeneration;
      final gate = Completer<void>();
      _popupDelayGate = gate;
      _pendingSurvey = survey;
      _pendingOnClosed = onClosed;
      _popupDelayTimer = Timer(delay, () {
        if (!gate.isCompleted) gate.complete();
      });
      await gate.future;
      if (generation != _popupDelayGeneration) return;
      _popupDelayTimer = null;
      _popupDelayGate = null;
      _pendingSurvey = null;
      _pendingOnClosed = null;
    }

    // Use the PosthogObserver's context to show the survey
    if (PosthogObserver.currentContext != null) {
      printIfDebug('[PostHog] Using PosthogObserver context for survey');
      return _showSurveyWithNavigator(
        survey,
        onShown,
        onResponse,
        onClosed,
        PosthogObserver.currentContext!,
      );
    }

    // If we can't show the survey, log an error
    printIfDebug(
      '[PostHog] Cannot show survey: No valid context found. To fix this make sure that you have installed PosthogObserver correctly in your app.',
    );
    if (delay > Duration.zero) onClosed(survey);
  }

  /// Shows a survey using a navigator context
  Future<void> _showSurveyWithNavigator(
    PostHogDisplaySurvey survey,
    OnSurveyShown onShown,
    OnSurveyResponse onResponse,
    OnSurveyClosed onClosed,
    BuildContext context,
  ) async {
    _isShowingSurvey = true;
    _currentSurvey = survey;
    final programmaticDismissal = Completer<void>();
    _programmaticDismissal = programmaticDismissal;
    try {
      final modalDismissal = showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        builder: (context) {
          final route = ModalRoute.of(context);
          if (_programmaticDismissal == programmaticDismissal &&
              !_isDismissingSurvey) {
            _currentSurveyRoute = route;
            if (_dismissSurveyWhenReady && route != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_currentSurveyRoute == route &&
                    _programmaticDismissal == programmaticDismissal) {
                  _dismissSurveyRoute(route, programmaticDismissal);
                }
              });
            }
          }
          return _buildSurveyWidget(survey, onShown, onResponse, (survey) {
            if (_programmaticDismissal != programmaticDismissal) {
              return;
            }
            _isDismissingSurvey = true;
            _currentSurveyRoute = null;
            onClosed(survey);
          });
        },
      );
      // removeRoute did not complete a route's future before Flutter 3.32.
      await Future.any([modalDismissal, programmaticDismissal.future]);
    } catch (e) {
      printIfDebug('[PostHog] Error showing survey: $e');
    } finally {
      if (_programmaticDismissal == programmaticDismissal) {
        _isShowingSurvey = false;
        _currentSurvey = null;
        _isDismissingSurvey = false;
        _dismissSurveyWhenReady = false;
        _currentSurveyRoute = null;
        _programmaticDismissal = null;
      }
    }
  }

  /// Builds the survey widget
  Widget _buildSurveyWidget(
    PostHogDisplaySurvey survey,
    OnSurveyShown onShown,
    OnSurveyResponse onResponse,
    OnSurveyClosed onClosed,
  ) {
    return SurveyBottomSheet(
      survey: survey,
      onShown: onShown,
      onResponse: onResponse,
      onClosed: onClosed,
      appearance: SurveyAppearance.fromPostHog(survey.appearance),
    );
  }

  void _dismissSurveyRoute(
    Route<dynamic> route,
    Completer<void> programmaticDismissal,
  ) {
    if (_isDismissingSurvey ||
        _currentSurveyRoute != route ||
        _programmaticDismissal != programmaticDismissal) {
      return;
    }

    _isDismissingSurvey = true;
    _dismissSurveyWhenReady = false;
    _currentSurveyRoute = null;
    programmaticDismissal.complete();
    route.navigator?.removeRoute(route);
  }

  void _cancelPendingSurvey() {
    final survey = _pendingSurvey;
    final onClosed = _pendingOnClosed;
    if (survey == null) return;

    _popupDelayGeneration++;
    _popupDelayTimer?.cancel();
    _popupDelayTimer = null;
    final gate = _popupDelayGate;
    _popupDelayGate = null;
    _pendingSurvey = null;
    _pendingOnClosed = null;
    if (gate != null && !gate.isCompleted) gate.complete();
    onClosed?.call(survey);
  }

  /// Hides any active survey
  void hideSurvey({PostHogDisplaySurvey? survey}) {
    if (_pendingSurvey != null &&
        (survey == null || identical(survey, _pendingSurvey))) {
      _cancelPendingSurvey();
      if (!_isShowingSurvey) return;
    }
    if (survey != null && !identical(survey, _currentSurvey)) return;
    if (!_isShowingSurvey || _isDismissingSurvey) {
      return;
    }

    final route = _currentSurveyRoute;
    if (route == null) {
      _dismissSurveyWhenReady = true;
      return;
    }
    _dismissSurveyRoute(route, _programmaticDismissal!);
  }
}
