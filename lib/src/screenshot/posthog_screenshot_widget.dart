import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;


import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/screenshot/mask/posthog_mask_controller.dart';

import 'change_detector.dart';
import 'native_communicator.dart';
import 'screenshot_capturer.dart';

class PostHogScreenshotWidget extends StatefulWidget {
  final Widget child;

  const PostHogScreenshotWidget({Key? key, required this.child}) : super(key: key);

  @override
  _PostHogScreenshotWidgetState createState() => _PostHogScreenshotWidgetState();
}

class _PostHogScreenshotWidgetState extends State<PostHogScreenshotWidget> {
  late final ChangeDetector _changeDetector;
  late final ScreenshotCapturer _screenshotCapturer;
  late final NativeCommunicator _nativeCommunicator;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    _screenshotCapturer = ScreenshotCapturer();
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
    final ui.Image? image = await _screenshotCapturer.captureScreenshot();
    if (image == null) {
      print('Error: Failed to capture screenshot.');
      return;
    }

    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      print('Error: Failed to convert image to byte data.');
      return;
    }

    Uint8List pngBytes = byteData.buffer.asUint8List();
    image.dispose();

    await _nativeCommunicator.sendImageAndRectsToNative(pngBytes);
  }

  Duration _getDebounceDuration() {
    final options = PostHogConfig().options;
    final sessionReplayConfig = options.sessionReplayConfig;

    if (Theme.of(context).platform == TargetPlatform.android) {
      return sessionReplayConfig?.androidDebouncerDelay ?? const Duration(milliseconds: 0);
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      return sessionReplayConfig?.iOSDebouncerDelay ?? const Duration(seconds: 1);
    } else {
      return const Duration(milliseconds: 500);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
        key: PostHogMaskController.instance.containerKey,
        child: Column(
          children: [
            Expanded(child: Container(child: widget.child)),
          ],
        ));
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
