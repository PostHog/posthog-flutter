import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/util/logging.dart';

import 'change_detector.dart';
import 'native_communicator.dart';
import 'screenshot/screenshot_capturer.dart';

class PostHogScreenshotWidget extends StatefulWidget {
  final Widget child;

  PostHogScreenshotWidget({Key? key, required this.child}) : super(key: key);

  @override
  _PostHogScreenshotWidgetState createState() =>
      _PostHogScreenshotWidgetState();
}

class _PostHogScreenshotWidgetState extends State<PostHogScreenshotWidget> {
  late final ChangeDetector _changeDetector;
  late final ScreenshotCapturer _screenshotCapturer;
  late final NativeCommunicator _nativeCommunicator;

  Timer? _debounceTimer;
  Duration _debounceDuration = const Duration(milliseconds: 1000);

  @override
  void initState() {
    final config = Posthog().config;

    super.initState();

    if (config == null) {
      return;
    }

    if (!config.sessionReplay) {
      return;
    }

    _debounceDuration = config.sessionReplayConfig.debouncerDelay;

    _screenshotCapturer = ScreenshotCapturer(config);
    _nativeCommunicator = NativeCommunicator();

    _changeDetector = ChangeDetector(_onChangeDetected);
    _changeDetector.start();
  }

  // This works as onRootViewsChangedListeners
  void _onChangeDetected() {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(_debounceDuration, () {
      generateSnapshot();
    });
  }

  Future<void> generateSnapshot() async {
    final isSessionReplayActive =
        await _nativeCommunicator.isSessionReplayActive();
    if (!isSessionReplayActive) {
      return;
    }

    final imageInfo = await _screenshotCapturer.captureScreenshot();
    if (imageInfo == null) {
      printIfDebug('Error: Failed to capture screenshot.');
      return;
    }

    if (imageInfo.shouldSendMetaEvent) {
      await _nativeCommunicator.sendMetaEvent(
          width: imageInfo.width, height: imageInfo.height);
    }

    // TODO: package:image/image.dart to convert to jpeg instead
    final ByteData? byteData =
        await imageInfo.image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      printIfDebug('Error: Failed to convert image to byte data.');
      return;
    }

    Uint8List pngBytes = byteData.buffer.asUint8List();
    imageInfo.image.dispose();

    await _nativeCommunicator.sendFullSnapshot(pngBytes,
        id: imageInfo.id, x: imageInfo.x, y: imageInfo.y);
  }

  Duration _getDebounceDuration() {
    final options = Posthog().config;

    final sessionReplayConfig = options?.sessionReplayConfig;

    return sessionReplayConfig?.debouncerDelay ??
        const Duration(milliseconds: 1000);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: PostHogMaskController.instance.containerKey,
      child: Column(
        children: [
          Expanded(child: Container(child: widget.child)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
