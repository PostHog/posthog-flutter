import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

class ScreenshotCapturer {
  final config = Posthog().config;
  final ImageMaskPainter _imageMaskPainter = ImageMaskPainter();

  ScreenshotCapturer();

  double _getPixelRatio({
    int? width,
    int? height,
    required double srcWidth,
    required double srcHeight,
  }) {
    assert((width == null) == (height == null));
    if (width == null || height == null) {
      return 1.0;
    }
    return min(width / srcWidth, height / srcHeight);
  }

  Future<ui.Image?> captureScreenshot() async {
    final context = PostHogMaskController.instance.containerKey.currentContext;
    if (context == null) {
      print('Error: screenshotKey has no context.');
      return null;
    }

    final renderObject = context.findRenderObject() as RenderRepaintBoundary?;
    if (renderObject == null) {
      print('Error: Unable to find RenderRepaintBoundary.');
      return null;
    }

    try {
      final srcWidth = renderObject.size.width;
      final srcHeight = renderObject.size.height;
      final pixelRatio =
          _getPixelRatio(srcWidth: srcWidth, srcHeight: srcHeight);

      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);

      final replayConfig = config!.postHogSessionReplayConfig;

      if (replayConfig.maskAllTextInputs || replayConfig.maskAllImages) {
        final screenElementsRects =
            await PostHogMaskController.instance.getCurrentScreenRects();

        if (screenElementsRects == null) {
          throw Exception('Failed to retrieve the element mask tree.');
        }

        final ui.Image maskedImage = await _imageMaskPainter.drawMaskedImage(
            image, screenElementsRects, pixelRatio);
        return maskedImage;
      }

      return image;
    } catch (e) {
      print('Error capturing image: $e');
      return null;
    }
  }
}
