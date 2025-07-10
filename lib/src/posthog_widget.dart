import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/surveys/posthog_surveys_provider.dart';
import 'package:posthog_flutter/src/util/logging.dart';

import 'posthog.dart';
import 'replay/change_detector.dart';
import 'replay/native_communicator.dart';
import 'replay/screenshot/screenshot_capturer.dart';

import 'surveys/models/posthog_display_survey.dart';
import 'surveys/models/survey_callbacks.dart';

@immutable
class PostHogWidget extends StatefulWidget {
  final Widget child;
  static final GlobalKey<PostHogWidgetState> globalKey =
      GlobalKey<PostHogWidgetState>();

  PostHogWidget({Key? key, required this.child}) : super(key: globalKey);

  @override
  PostHogWidgetState createState() => PostHogWidgetState();
}

class PostHogWidgetState extends State<PostHogWidget> {
  ChangeDetector? _changeDetector;
  ScreenshotCapturer? _screenshotCapturer;
  NativeCommunicator? _nativeCommunicator;

  Timer? _throttleTimer;
  bool _isThrottling = false;
  Duration _throttleDuration = const Duration(milliseconds: 1000);

  @override
  void initState() {
    super.initState();

    final config = Posthog().config;
    if (config == null || !config.sessionReplay) {
      return;
    }

    _throttleDuration = config.sessionReplayConfig.throttleDelay;

    _screenshotCapturer = ScreenshotCapturer(config);
    _nativeCommunicator = NativeCommunicator();

    _changeDetector = ChangeDetector(_onChangeDetected);
    _changeDetector?.start();
  }

  // This works as onRootViewsChangedListeners
  void _onChangeDetected() {
    if (_isThrottling) {
      // If throttling is active, ignore this call
      return;
    }

    // Start throttling
    _isThrottling = true;

    // Execute the snapshot generation
    _generateSnapshot();

    _throttleTimer?.cancel();
    // Reset throttling after the duration
    _throttleTimer = Timer(_throttleDuration, () {
      _isThrottling = false;
    });
  }

  Future<void> _generateSnapshot() async {
    // Ensure no asynchronous calls occur before this function,
    // as it relies on a consistent state.
    final imageInfo = await _screenshotCapturer?.captureScreenshot();
    if (imageInfo == null) {
      return;
    }

    if (imageInfo.shouldSendMetaEvent) {
      await _nativeCommunicator?.sendMetaEvent(
          width: imageInfo.width,
          height: imageInfo.height,
          screen: Posthog().currentScreen);
    }

    await _nativeCommunicator?.sendFullSnapshot(imageInfo.imageBytes,
        id: imageInfo.id, x: imageInfo.x, y: imageInfo.y);
  }

  @override
  Widget build(BuildContext context) {
    return Localizations(
      locale: const Locale('en', 'US'),
      delegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: RepaintBoundary(
        key: PostHogMaskController.instance.containerKey,
        child: Column(
          children: [
            Expanded(
              child: MaterialApp(
                navigatorObservers: [],
                home: PostHogSurveysProvider(
                  child: Container(child: widget.child),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> showSurvey(
    PostHogDisplaySurvey survey,
    OnSurveyShown onShown,
    OnSurveyResponse onResponse,
    OnSurveyClosed onClosed,
  ) async {
    if (!mounted) return;

    final surveysProvider = PostHogSurveysProvider.globalKey.currentState;
    if (surveysProvider != null) {
      await surveysProvider.showSurvey(survey, onShown, onResponse, onClosed);
    } else {
      printIfDebug(
          '[PostHog] Error: PostHogSurveysProvider not found in widget tree');
    }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _changeDetector?.stop();
    _changeDetector = null;
    _screenshotCapturer = null;
    _nativeCommunicator = null;
    super.dispose();
  }

  /// Cleans up any active surveys
  Future<void> cleanupSurveys() async {
    final surveysProvider = PostHogSurveysProvider.globalKey.currentState;
    if (surveysProvider != null) {
      surveysProvider.hideSurvey();
    } else {
      printIfDebug(
          '[PostHog] Error: PostHogSurveysProvider not found in widget tree');
    }
  }
}
