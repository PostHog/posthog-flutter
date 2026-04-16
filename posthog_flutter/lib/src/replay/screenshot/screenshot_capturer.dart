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

  /// Computes a hash of the full raw RGBA byte array for change detection.
  /// This avoids retaining the full image bytes while still hashing every byte.
  int _computeImageHash(Uint8List bytes) {
    var hash = 0x811c9dc5; // FNV offset basis (32-bit)
    final length = bytes.length;

    // Always include the length in the hash.
    hash ^= length;
    hash = (hash * 0x01000193) & 0x7fffffff;

    for (var i = 0; i < length; i++) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0x7fffffff;
    }

    return hash;
  }

  Future<ImageInfo?> captureScreenshot() {
    _cancelled = false;

    final context = PostHogMaskController.instance.containerKey.currentContext;
    if (context == null) {
      return Future.value(null);
    }

    final renderObject = context.findRenderObject() as RenderRepaintBoundary?;
    if (renderObject == null ||
        !renderObject.hasSize ||
        !renderObject.size.isValidSize) {
      return Future.value(null);
    }

    final statusView = _snapshotManager.getStatus(renderObject);

    final shouldSendMetaEvent = !statusView.sentMetaEvent;

    // Get the global position of the widget
    final globalPosition = renderObject.localToGlobal(Offset.zero);

    final viewId = identityHashCode(renderObject);

    final Completer<ImageInfo?> completer = Completer<ImageInfo?>();

    try {
      final srcWidth = renderObject.size.width;
      final srcHeight = renderObject.size.height;
      final pixelRatio = _getPixelRatio(
        srcWidth: srcWidth,
        srcHeight: srcHeight,
      );

      final syncImage = renderObject.toImage(pixelRatio: pixelRatio);

      final replayConfig = _config.sessionReplayConfig;

      final postHogWidgetWrapperElements =
          PostHogMaskController.instance.getPostHogWidgetWrapperElements();

      // call getCurrentScreenRects if really necessary
      List<ElementData>? elementsDataWidgets;
      if (replayConfig.maskAllTexts || replayConfig.maskAllImages) {
        elementsDataWidgets =
            PostHogMaskController.instance.getCurrentWidgetsElements();
      }

      /// we firstly get current image (syncImage) and masks
      /// (postHogWidgetWrapperElements, elementsDataWidgets) synchronously and
      /// then executed the main process asynchronous
      ui.Image? image;
      ui.PictureRecorder? recorder;
      ui.Picture? picture;
      ui.Image? finalImage;

      Future(() async {
        final isSessionReplayActive =
            await _nativeCommunicator.isSessionReplayActive();
        if (_cancelled) {
          completer.complete(null);
          return;
        }

        // wait the UI to settle
        await SchedulerBinding.instance.endOfFrame;
        image = await syncImage;
        final currentImage = image;
        if (_cancelled) {
          currentImage?.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        if (currentImage == null ||
            !isSessionReplayActive ||
            !currentImage.isValidSize) {
          _snapshotManager.clear();
          currentImage?.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        recorder = ui.PictureRecorder();
        final currentRecorder = recorder;
        if (currentRecorder == null) {
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }
        final canvas = Canvas(currentRecorder);

        // using rawRgba for the diff check because it is faster than png encoding
        Uint8List? imageBytes = await _getImageBytes(
          currentImage,
          format: ui.ImageByteFormat.rawRgba,
        );
        if (_cancelled) {
          currentRecorder.endRecording().dispose();
          recorder = null;
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        if (imageBytes == null || imageBytes.isEmpty) {
          printIfDebug(
            'Error: Failed to convert image byte data to Uint8List.',
          );
          currentRecorder.endRecording().dispose();
          recorder = null;
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        final currentHash = _computeImageHash(imageBytes);
        imageBytes = null;

        if (currentHash == statusView.imageBytesHash) {
          printIfDebug(
            'Debug: Snapshot is the same as the last one, nothing changed, do nothing.',
          );
          currentRecorder.endRecording().dispose();
          recorder = null;
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        statusView.imageBytesHash = currentHash;

        try {
          canvas.drawImage(currentImage, Offset.zero, Paint());
        } finally {
          currentImage.dispose();
          image = null;
        }

        if (_cancelled) {
          currentRecorder.endRecording().dispose();
          recorder = null;
          completer.complete(null);
          return;
        }

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

        picture = currentRecorder.endRecording();
        recorder = null;

        final currentPicture = picture;
        if (currentPicture == null) {
          completer.complete(null);
          return;
        }

        try {
          finalImage = await currentPicture.toImage(
            srcWidth.toInt(),
            srcHeight.toInt(),
          );

          final currentFinalImage = finalImage;
          if (_cancelled) {
            currentFinalImage?.dispose();
            finalImage = null;
            completer.complete(null);
            return;
          }

          if (currentFinalImage == null || !currentFinalImage.isValidSize) {
            currentFinalImage?.dispose();
            finalImage = null;
            completer.complete(null);
            return;
          }

          try {
            final pngBytes = await _getImageBytes(currentFinalImage);
            if (_cancelled || pngBytes == null || pngBytes.isEmpty) {
              completer.complete(null);
              return;
            }

            final imageInfo = ImageInfo(
              viewId,
              globalPosition.dx.toInt(),
              globalPosition.dy.toInt(),
              srcWidth.toInt(),
              srcHeight.toInt(),
              shouldSendMetaEvent,
              pngBytes,
            );
            _snapshotManager.updateStatus(
              renderObject,
              shouldSendMetaEvent: shouldSendMetaEvent,
            );
            completer.complete(imageInfo);
          } finally {
            currentFinalImage.dispose();
            finalImage = null;
          }
        } finally {
          currentPicture.dispose();
          picture = null;
        }
      }).catchError((error) {
        finalImage?.dispose();
        finalImage = null;
        picture?.dispose();
        picture = null;
        final currentRecorder = recorder;
        if (currentRecorder != null) {
          currentRecorder.endRecording().dispose();
          recorder = null;
        }
        image?.dispose();
        image = null;

        printIfDebug('Error capturing image: $error');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      return completer.future;
    } catch (e) {
      printIfDebug('Error initializing capture: $e');
      return Future.value(null);
    }
  }
}
