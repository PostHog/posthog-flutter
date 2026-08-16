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
  Route<dynamic>? _currentSurveyRoute;

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
    try {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        builder: (context) {
          _currentSurveyRoute = ModalRoute.of(context);
          return _buildSurveyWidget(survey, onShown, onResponse, (s) {
            _isShowingSurvey = false;
            _currentSurveyRoute = null;
            onClosed(s);
          });
        },
      );
    } catch (e) {
      printIfDebug('[PostHog] Error showing survey: $e');
    } finally {
      _isShowingSurvey = false;
      _currentSurveyRoute = null;
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

  /// Hides any active survey
  void hideSurvey() {
    final route = _currentSurveyRoute;
    if (_isShowingSurvey && route != null) {
      route.navigator?.removeRoute(route);
      _currentSurveyRoute = null;
    }
    _isShowingSurvey = false;
  }
}
