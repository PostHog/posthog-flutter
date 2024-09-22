import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/posthog_config.dart';

import 'change_detector.dart';
import 'image_masker.dart';
import 'native_communicator.dart';
import 'screenshot_capturer.dart';
import 'sensitive_widget_detector.dart';

final GlobalKey _screenshotKey =
    GlobalKey(debugLabel: 'posthog_screenshot_widget');

class PostHogScreenshotWidget extends StatefulWidget {
  final Widget child;

  const PostHogScreenshotWidget({Key? key, required this.child})
      : super(key: key);

  @override
  _PostHogScreenshotWidgetState createState() =>
      _PostHogScreenshotWidgetState();
}

class _PostHogScreenshotWidgetState extends State<PostHogScreenshotWidget> {
  late final ChangeDetector _changeDetector;
  late final SensitiveWidgetDetector _sensitiveWidgetDetector;
  late final ScreenshotCapturer _screenshotCapturer;
  late final ImageMasker _imageMasker;
  late final NativeCommunicator _nativeCommunicator;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    final options = PostHogConfig().options;
    final sessionReplayConfig = options.sessionReplayConfig;

    _sensitiveWidgetDetector = SensitiveWidgetDetector(
      maskAllTextInputs: sessionReplayConfig?.maskAllTextInputs ?? true,
      maskAllImages: sessionReplayConfig?.maskAllImages ?? true,
    );
    _screenshotCapturer = ScreenshotCapturer(_screenshotKey);
    _imageMasker = ImageMasker();
    _nativeCommunicator = NativeCommunicator();

    _changeDetector = ChangeDetector(_onChangeDetected);
    _changeDetector.start();
  }

  void _onChangeDetected() {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(_getDebounceDuration(), () {
      _captureAndSendScreenshot();
    });
  }

  Future<void> _captureAndSendScreenshot() async {
    final context = _screenshotKey.currentContext;
    if (context == null) {
      print('Error: _screenshotKey has no context.');
      return;
    }

    final originalImage = await _screenshotCapturer.captureScreenshot();
    if (originalImage == null) {
      return;
    }

    /*
    * NOT FINISHED - This part of the code is still a work in progress.
    * Need to understand how widget capture works for individual screens,
    * not the entire app. The goal is to correctly filter and handle
    * the widget tree for each screen context.
    *
    final maskedAreas =
        _sensitiveWidgetDetector.findSensitiveAreas(context as Element);

    final maskedImage =
        await _imageMasker.applyMasks(originalImage, maskedAreas);
    */

    ByteData? byteData =
        await originalImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      print('Error: Unable to convert image to byte data.');
      originalImage.dispose();
      return;
    }

    Uint8List? pngBytes = byteData.buffer.asUint8List();
    originalImage.dispose();

    await _nativeCommunicator.sendImageToNative(pngBytes);

    byteData = null;
    pngBytes = null;
  }

  Duration _getDebounceDuration() {
    final options = PostHogConfig().options;
    final sessionReplayConfig = options.sessionReplayConfig;

    if (Theme.of(context).platform == TargetPlatform.android) {
      return sessionReplayConfig?.androidDebouncerDelay ??
          const Duration(milliseconds: 0);
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      return sessionReplayConfig?.iOSDebouncerDelay ??
          const Duration(seconds: 1);
    } else {
      return const Duration(milliseconds: 500);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _screenshotKey,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
