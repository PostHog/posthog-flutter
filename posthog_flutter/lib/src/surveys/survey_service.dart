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
/// Values above one day are capped at one day.
Duration surveyPopupDelay(double? seconds) {
  if (seconds == null || seconds.isNaN || seconds <= 0) {
    return Duration.zero;
  }
  const maxDelay = Duration(days: 1);
  if (seconds >= maxDelay.inSeconds) return maxDelay;
  return Duration(milliseconds: (seconds * 1000).round());
}

/// Card alignment for [position] (`appearance.position`).
///
/// Returns null for bottom center, a missing value, or an unknown value, which
/// all keep the bottom sheet like iOS does.
Alignment? surveyCardAlignment(String? position) {
  switch (position) {
    case 'top_left':
      return Alignment.topLeft;
    case 'top_center':
      return Alignment.topCenter;
    case 'top_right':
      return Alignment.topRight;
    case 'middle_left':
      return Alignment.centerLeft;
    case 'middle_center':
      return Alignment.center;
    case 'middle_right':
      return Alignment.centerRight;
    case 'left':
      return Alignment.bottomLeft;
    case 'right':
      return Alignment.bottomRight;
    default:
      return null;
  }
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
  Completer<bool>? _pendingShow;
  Timer? _popupDelayTimer;
  PostHogDisplaySurvey? _delayedSurvey;

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

    _cancelPopupDelay();

    final delay = surveyPopupDelay(survey.appearance?.surveyPopupDelaySeconds);
    if (delay > Duration.zero && !await _waitForPopupDelay(survey, delay)) {
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

  /// Completes with true once the delay has elapsed, or false when the wait
  /// was cancelled by [hideSurvey] or replaced by a newer survey.
  Future<bool> _waitForPopupDelay(
    PostHogDisplaySurvey survey,
    Duration delay,
  ) {
    final wait = _startPendingShow();
    _delayedSurvey = survey;
    _popupDelayTimer = Timer(delay, () {
      _clearPopupDelay();
      _endPendingShow(show: true);
    });
    return wait;
  }

  /// Completes with true once [PosthogObserver] reports a context, or false
  /// when the wait was cancelled by [hideSurvey] or replaced by a newer survey.
  Future<bool> _waitForContext() => _startPendingShow();

  Future<bool> _startPendingShow() {
    _endPendingShow(show: false);
    final pendingShow = Completer<bool>();
    _pendingShow = pendingShow;
    return pendingShow.future;
  }

  void _endPendingShow({required bool show}) {
    final pendingShow = _pendingShow;
    _pendingShow = null;
    pendingShow?.complete(show);
  }

  /// Called by [PosthogObserver] when it has a context, so a survey that
  /// arrived before then can be shown.
  void onContextAvailable() {
    if (_popupDelayTimer == null) _endPendingShow(show: true);
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
      final cardAlignment = surveyCardAlignment(survey.appearance?.position);
      Widget builder(BuildContext context) {
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
      }

      final modalDismissal = cardAlignment == null
          ? showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              isDismissible: false,
              builder: builder,
            )
          : showGeneralDialog<void>(
              context: context,
              useRootNavigator: true,
              barrierDismissible: false,
              barrierColor: Colors.black54,
              pageBuilder: (context, _, __) =>
                  _buildSurveyCard(context, cardAlignment, builder(context)),
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

  /// Shows the survey as a card at [alignment].
  Widget _buildSurveyCard(
    BuildContext context,
    Alignment alignment,
    Widget survey,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16) +
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              // The padding above already lifts the card over the keyboard.
              // Builder reads MediaQuery inside SafeArea, so the sheet's own
              // SafeArea adds nothing.
              child: Builder(
                builder: (context) => MediaQuery.removeViewInsets(
                  context: context,
                  removeBottom: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: survey,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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

  /// Drops a survey still waiting out its delay without calling onClosed:
  /// the user never saw it, so it must not be marked seen or dismissed.
  void _cancelPopupDelay() {
    if (_delayedSurvey == null) return;

    _popupDelayTimer?.cancel();
    _clearPopupDelay();
    _endPendingShow(show: false);
  }

  void _clearPopupDelay() {
    _popupDelayTimer = null;
    _delayedSurvey = null;
  }

  /// Hides any active survey
  void hideSurvey({PostHogDisplaySurvey? survey}) {
    if (survey == null || identical(survey, _delayedSurvey)) {
      _cancelPopupDelay();
    }
    if (survey == null) _endPendingShow(show: false);
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
