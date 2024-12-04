import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/vendor/equality.dart';
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
  Uint8List? _lastSnapshot;
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

    // using png because its compressed, the native SDKs will decompress it
    // and transform to jpeg if needed (soon webp)
    // https://github.com/brendan-duncan/image does not have webp encoding
    final ByteData? byteData =
        await imageInfo.image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      printIfDebug('Error: Failed to convert image to byte data.');
      imageInfo.image.dispose();
      return;
    }

    Uint8List pngBytes = byteData.buffer.asUint8List();
    imageInfo.image.dispose();

    if (pngBytes.isEmpty) {
      printIfDebug('Error: Failed to convert image byte data to Uint8List.');
      return;
    }

    if (const PHListEquality().equals(pngBytes, _lastSnapshot)) {
      printIfDebug('Error: Snapshot is the same as the last one.');
      return;
    }

    _lastSnapshot = pngBytes;

    await _nativeCommunicator?.sendFullSnapshot(pngBytes,
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
    _lastSnapshot = null;

    super.dispose();
  }
}
