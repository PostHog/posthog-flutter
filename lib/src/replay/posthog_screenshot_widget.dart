import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

import 'change_detector.dart';
import 'native_communicator.dart';
import 'screenshot/screenshot_capturer.dart';

class PostHogScreenshotWidget extends StatefulWidget {
  final Widget child;

  PostHogScreenshotWidget({Key? key, required this.child}) : super(key: key);

  @override
  _PostHogScreenshotWidgetState createState() => _PostHogScreenshotWidgetState();
}

class _PostHogScreenshotWidgetState extends State<PostHogScreenshotWidget> {
  late final ChangeDetector _changeDetector;
  late final ScreenshotCapturer _screenshotCapturer;
  late final NativeCommunicator _nativeCommunicator;

  Timer? _debounceTimer;

  Uint8List? _lastImageBytes;
  bool _sentFullSnapshot = false;
  final int _wireframeId = 1;

  @override
  void initState() {
    super.initState();

    if (!PostHogConfig().options.enableSessionReplay) {
      return;
    }

    _screenshotCapturer = ScreenshotCapturer();
    _nativeCommunicator = NativeCommunicator();

    _changeDetector = ChangeDetector(_onChangeDetected);
    _changeDetector.start();
  }

  // This works as onRootViewsChangedListeners
  void _onChangeDetected() {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(_getDebounceDuration(), () {
      generateSnapshot();
    });
  }

  Future<void> generateSnapshot() async {
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

    if (!_sentFullSnapshot) {

      await _nativeCommunicator.sendFullSnapshot(pngBytes, id: _wireframeId);
      _lastImageBytes = pngBytes;
      _sentFullSnapshot = true;
    } else {
      if (_lastImageBytes == null || !listEquals(_lastImageBytes, pngBytes)) {
        await _nativeCommunicator.sendIncrementalSnapshot(pngBytes, id: _wireframeId);
        _lastImageBytes = pngBytes;
      } else {
        // Images are the same, do nothing for while
      }
    }
  }

  Duration _getDebounceDuration() {
    final options = PostHogConfig().options;
    final sessionReplayConfig = options.sessionReplayConfig;

    if (Theme.of(context).platform == TargetPlatform.android) {
      return sessionReplayConfig?.androidDebouncerDelay ?? const Duration(milliseconds: 100);
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
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
