import 'dart:async';

import 'package:flutter/material.dart';

import '../util/logging.dart';
import '../posthog_observer.dart';
import 'models/posthog_display_survey.dart';
import 'models/survey_callbacks.dart';
import 'models/survey_appearance.dart';
import 'widgets/survey_bottom_sheet.dart';

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
  Completer<bool>? _contextWait;

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

    var context = PosthogObserver.currentContext;
    if (context == null) {
      printIfDebug(
        '[PostHog] No valid context to show the survey yet, it will be shown on the next navigation. If it never shows, make sure that you have installed PosthogObserver correctly in your app.',
      );
      // The native SDK keeps this survey active until it is closed, and closing
      // it would record a dismissal for a survey the user never saw.
      do {
        if (!await _waitForContext() || _isShowingSurvey) return;
        context = PosthogObserver.currentContext;
      } while (context == null);
    }
    if (!context.mounted) return;

    printIfDebug('[PostHog] Using PosthogObserver context for survey');
    return _showSurveyWithNavigator(
      survey,
      onShown,
      onResponse,
      onClosed,
      context,
    );
  }

  /// Completes with true once [PosthogObserver] reports a context, or false
  /// when the wait was cancelled by [hideSurvey] or replaced by a newer survey.
  Future<bool> _waitForContext() {
    _endContextWait(show: false);
    final contextWait = Completer<bool>();
    _contextWait = contextWait;
    return contextWait.future;
  }

  void _endContextWait({required bool show}) {
    final contextWait = _contextWait;
    _contextWait = null;
    contextWait?.complete(show);
  }

  /// Called by [PosthogObserver] when it has a context, so a survey that
  /// arrived before then can be shown.
  void onContextAvailable() => _endContextWait(show: true);

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

  /// Hides any active survey
  void hideSurvey({PostHogDisplaySurvey? survey}) {
    if (survey == null) _endContextWait(show: false);
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
