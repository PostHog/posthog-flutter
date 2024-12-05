import 'dart:async';

import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/util/logging.dart';

import 'replay/change_detector.dart';
import 'replay/native_communicator.dart';
import 'replay/screenshot/screenshot_capturer.dart';

class PostHogWidget extends StatefulWidget {
  final Widget child;

  const PostHogWidget({super.key, required this.child});

  @override
  PostHogWidgetState createState() => PostHogWidgetState();
}

class PostHogWidgetState extends State<PostHogWidget> {
  ChangeDetector? _changeDetector;
  ScreenshotCapturer? _screenshotCapturer;
  NativeCommunicator? _nativeCommunicator;

  Timer? _debounceTimer;
  Duration _debounceDuration = const Duration(milliseconds: 1000);

  @override
  void initState() {
    super.initState();

    final config = Posthog().config;
    if (config == null || !config.sessionReplay) {
      return;
    }

    _debounceDuration = config.sessionReplayConfig.debouncerDelay;

    _screenshotCapturer = ScreenshotCapturer(config);
    _nativeCommunicator = NativeCommunicator();

    _changeDetector = ChangeDetector(_onChangeDetected);
    _changeDetector?.start();
  }

  // This works as onRootViewsChangedListeners
  void _onChangeDetected() {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(_debounceDuration, () {
      _generateSnapshot();
    });
  }

  Future<void> _generateSnapshot() async {
    final isSessionReplayActive =
        await _nativeCommunicator?.isSessionReplayActive() ?? false;
    if (!isSessionReplayActive) {
      return;
    }

    final imageInfo = await _screenshotCapturer?.captureScreenshot();
    if (imageInfo == null) {
      printIfDebug('Error: Failed to capture screenshot.');
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
    _debounceTimer = null;
    _changeDetector?.stop();
    _changeDetector = null;
    _screenshotCapturer = null;
    _nativeCommunicator = null;

    super.dispose();
  }
}
