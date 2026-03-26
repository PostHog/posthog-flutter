import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/image_extension.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/native_communicator.dart';
import 'package:posthog_flutter/src/replay/screenshot/snapshot_manager.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';
import 'package:posthog_flutter/src/util/logging.dart';

class ImageInfo {
  final int id;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool shouldSendMetaEvent;
  final Uint8List imageBytes;

  ImageInfo(
    this.id,
    this.x,
    this.y,
    this.width,
    this.height,
    this.shouldSendMetaEvent,
    this.imageBytes,
  );
}

class ViewTreeSnapshotStatus {
  bool sentMetaEvent = false;

  /// Hash of the last captured raw RGBA image bytes.
  /// We store only a hash instead of the full byte array to avoid
  /// holding ~8MB+ of raw pixel data in memory permanently.
  int? imageBytesHash;

  ViewTreeSnapshotStatus(this.sentMetaEvent);
}

class ScreenshotCapturer {
  final PostHogConfig _config;
  final ImageMaskPainter _imageMaskPainter = ImageMaskPainter();
  final _nativeCommunicator = NativeCommunicator();
  final _snapshotManager = SnapshotManager();

  bool _cancelled = false;

  ScreenshotCapturer(this._config);

  /// Cancels any in-flight capture. After calling this, any ongoing
  /// [captureScreenshot] will return null at its next await point.
  void cancel() {
    _cancelled = true;
  }

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

  Future<Uint8List?> _getImageBytes(
    ui.Image img, {
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
  }) async {
    try {
      final ByteData? byteData = await img.toByteData(format: format);
      if (byteData == null || byteData.lengthInBytes == 0) {
        printIfDebug('Error: Failed to convert image to byte data.');
        return null;
      }
      return byteData.buffer.asUint8List();
    } catch (e) {
      printIfDebug('Error converting image to byte data: $e');
      return null;
    }
  }

  /// Computes a fast hash of a byte array for change detection.
  /// Uses a sampling approach for large arrays to avoid iterating every byte.
  static int _computeImageHash(Uint8List bytes) {
    // FNV-1a inspired hash with sampling for large buffers.
    // For buffers > 64KB, sample every Nth byte to keep it fast.
    const sampleThreshold = 64 * 1024;
    var hash = 0x811c9dc5; // FNV offset basis (32-bit)
    final length = bytes.length;

    // Always include the length in the hash
    hash ^= length;
    hash = (hash * 0x01000193) & 0x7fffffff;

    if (length <= sampleThreshold) {
      // Small buffer: hash every byte
      for (var i = 0; i < length; i++) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0x7fffffff;
      }
    } else {
      // Large buffer: sample bytes at regular intervals
      // Sample ~4096 evenly-spaced bytes + first/last 512 bytes
      final step = length ~/ 4096;

      // First 512 bytes
      final headEnd = min(512, length);
      for (var i = 0; i < headEnd; i++) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0x7fffffff;
      }

      // Evenly spaced samples
      for (var i = headEnd; i < length - 512; i += step) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0x7fffffff;
      }

      // Last 512 bytes
      final tailStart = max(length - 512, headEnd);
      for (var i = tailStart; i < length; i++) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0x7fffffff;
      }
    }

    return hash;
  }

  Future<ImageInfo?> captureScreenshot() async {
    _cancelled = false;

    final context = PostHogMaskController.instance.containerKey.currentContext;
    if (context == null) {
      return null;
    }

    final renderObject = context.findRenderObject() as RenderRepaintBoundary?;
    if (renderObject == null ||
        !renderObject.hasSize ||
        !renderObject.size.isValidSize) {
      return null;
    }

    final statusView = _snapshotManager.getStatus(renderObject);
    final shouldSendMetaEvent = !statusView.sentMetaEvent;
    final globalPosition = renderObject.localToGlobal(Offset.zero);
    final viewId = identityHashCode(renderObject);

    final srcWidth = renderObject.size.width;
    final srcHeight = renderObject.size.height;
    final pixelRatio = _getPixelRatio(
      srcWidth: srcWidth,
      srcHeight: srcHeight,
    );

    final replayConfig = _config.sessionReplayConfig;

    final postHogWidgetWrapperElements =
        PostHogMaskController.instance.getPostHogWidgetWrapperElements();

    // call getCurrentScreenRects if really necessary
    List<ElementData>? elementsDataWidgets;
    if (replayConfig.maskAllTexts || replayConfig.maskAllImages) {
      elementsDataWidgets =
          PostHogMaskController.instance.getCurrentWidgetsElements();
    }

    // Capture the image synchronously (starts the rasterization)
    final syncImage = renderObject.toImage(pixelRatio: pixelRatio);

    try {
      final isSessionReplayActive =
          await _nativeCommunicator.isSessionReplayActive();
      if (_cancelled) return null;

      // wait the UI to settle
      await SchedulerBinding.instance.endOfFrame;
      if (_cancelled) return null;

      final image = await syncImage;
      if (_cancelled) {
        image.dispose();
        return null;
      }

      if (!isSessionReplayActive || !image.isValidSize) {
        _snapshotManager.clear();
        image.dispose();
        return null;
      }

      // Get raw RGBA for change detection
      Uint8List? imageBytes;
      try {
        imageBytes = await _getImageBytes(
          image,
          format: ui.ImageByteFormat.rawRgba,
        );
      } catch (e) {
        image.dispose();
        printIfDebug('Error getting image bytes: $e');
        return null;
      }

      if (_cancelled) {
        image.dispose();
        return null;
      }

      if (imageBytes == null || imageBytes.isEmpty) {
        printIfDebug(
          'Error: Failed to convert image byte data to Uint8List.',
        );
        image.dispose();
        return null;
      }

      // Use hash-based comparison instead of storing full raw RGBA bytes (~8MB)
      final currentHash = _computeImageHash(imageBytes);
      // Release the raw RGBA bytes immediately — we only need the hash
      imageBytes = null;

      if (currentHash == statusView.imageBytesHash) {
        printIfDebug(
          'Debug: Snapshot is the same as the last one, nothing changed, do nothing.',
        );
        image.dispose();
        return null;
      }

      statusView.imageBytesHash = currentHash;

      // Draw the original image onto a canvas for masking
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      try {
        canvas.drawImage(image, Offset.zero, Paint());
      } finally {
        image.dispose();
      }

      if (_cancelled) {
        recorder.endRecording().dispose();
        return null;
      }

      // Apply masks
      if (replayConfig.maskAllTexts || replayConfig.maskAllImages) {
        if (elementsDataWidgets != null && elementsDataWidgets.isNotEmpty) {
          _imageMaskPainter.drawMaskedImage(
            canvas,
            elementsDataWidgets,
            pixelRatio,
          );
        }
      } else {
        if (postHogWidgetWrapperElements != null &&
            postHogWidgetWrapperElements.isNotEmpty) {
          _imageMaskPainter.drawMaskedImage(
            canvas,
            postHogWidgetWrapperElements,
            pixelRatio,
          );
        }
      }

      final picture = recorder.endRecording();
      ui.Image? finalImage;
      try {
        finalImage = await picture.toImage(
          srcWidth.toInt(),
          srcHeight.toInt(),
        );

        if (_cancelled) {
          return null;
        }

        if (!finalImage.isValidSize) {
          return null;
        }

        final pngBytes = await _getImageBytes(finalImage);
        if (_cancelled || pngBytes == null || pngBytes.isEmpty) {
          return null;
        }

        _snapshotManager.updateStatus(
          renderObject,
          shouldSendMetaEvent: shouldSendMetaEvent,
        );

        return ImageInfo(
          viewId,
          globalPosition.dx.toInt(),
          globalPosition.dy.toInt(),
          srcWidth.toInt(),
          srcHeight.toInt(),
          shouldSendMetaEvent,
          pngBytes,
        );
      } finally {
        finalImage?.dispose();
        picture.dispose();
      }
    } catch (e) {
      printIfDebug('Error capturing screenshot: $e');
      return null;
    }
  }
}
