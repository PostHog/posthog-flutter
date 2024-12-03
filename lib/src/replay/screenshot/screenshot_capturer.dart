import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/util/logging.dart';

class ImageInfo {
  final ui.Image image;
  final int id;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool shouldSendMetaEvent;

  ImageInfo(this.image, this.id, this.x, this.y, this.width, this.height,
      this.shouldSendMetaEvent);
}

class ViewTreeSnapshotStatus {
  bool sentMetaEvent = false;
  ViewTreeSnapshotStatus(this.sentMetaEvent);
}

class ScreenshotCapturer {
  final PostHogConfig _config;
  final ImageMaskPainter _imageMaskPainter = ImageMaskPainter();
  // Expando is the equivalent of weakref
  final _views = Expando();

  ScreenshotCapturer(this._config);

  double _getPixelRatio({
    int? width,
    int? height,
    required double srcWidth,
    required double srcHeight,
  }) {
    if (width == null || height == null || srcWidth <= 0 || srcHeight <= 0) {
      return 1.0;
    }
    return min(width / srcWidth, height / srcHeight);
  }

  void _updateStatusView(bool shouldSendMetaEvent, RenderObject renderObject,
      ViewTreeSnapshotStatus statusView) {
    if (shouldSendMetaEvent) {
      statusView.sentMetaEvent = true;
      _views[renderObject] = statusView;
    }
  }

  Future<ImageInfo?> captureScreenshot() async {
    final context = PostHogMaskController.instance.containerKey.currentContext;
    if (context == null) {
      return null;
    }

    final renderObject = context.findRenderObject() as RenderRepaintBoundary?;
    if (renderObject == null) {
      return null;
    }

    final statusView = (_views[renderObject] as ViewTreeSnapshotStatus?) ??
        ViewTreeSnapshotStatus(false);

    final shouldSendMetaEvent = !statusView.sentMetaEvent;

    // Get the global position of the widget
    final globalPosition = renderObject.localToGlobal(Offset.zero);

    final viewId = identityHashCode(renderObject);

    try {
      final srcWidth = renderObject.size.width;
      final srcHeight = renderObject.size.height;
      final pixelRatio =
          _getPixelRatio(srcWidth: srcWidth, srcHeight: srcHeight);

      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);

      final replayConfig = _config.sessionReplayConfig;

      if (replayConfig.maskAllTexts || replayConfig.maskAllImages) {
        final screenElementsRects =
            await PostHogMaskController.instance.getCurrentScreenRects();

        if (screenElementsRects != null) {
          final ui.Image maskedImage = await _imageMaskPainter.drawMaskedImage(
              image, screenElementsRects, pixelRatio);
          final imageInfo = ImageInfo(
              maskedImage,
              viewId,
              globalPosition.dx.toInt(),
              globalPosition.dy.toInt(),
              srcWidth.toInt(),
              srcHeight.toInt(),
              shouldSendMetaEvent);
          _updateStatusView(shouldSendMetaEvent, renderObject, statusView);
          return imageInfo;
        }
      }

      final imageInfo = ImageInfo(
          image,
          viewId,
          globalPosition.dx.toInt(),
          globalPosition.dy.toInt(),
          srcWidth.toInt(),
          srcHeight.toInt(),
          shouldSendMetaEvent);
      _updateStatusView(shouldSendMetaEvent, renderObject, statusView);
      return imageInfo;
    } catch (e) {
      printIfDebug('Error capturing image: $e');
      return null;
    }
  }
}
