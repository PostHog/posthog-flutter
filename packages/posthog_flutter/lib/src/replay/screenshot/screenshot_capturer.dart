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
import 'package:posthog_flutter/src/replay/vendor/equality.dart';
import 'package:posthog_flutter/src/util/logging.dart';

class ImageInfo {
  final int id;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool shouldSendMetaEvent;
  final Uint8List imageBytes;

  ImageInfo(this.id, this.x, this.y, this.width, this.height,
      this.shouldSendMetaEvent, this.imageBytes);
}

class ViewTreeSnapshotStatus {
  bool sentMetaEvent = false;
  Uint8List? imageBytes;
  ViewTreeSnapshotStatus(this.sentMetaEvent);
}

class ScreenshotCapturer {
  final PostHogConfig _config;
  final ImageMaskPainter _imageMaskPainter = ImageMaskPainter();
  final _nativeCommunicator = NativeCommunicator();
  final _snapshotManager = SnapshotManager();

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

  Future<Uint8List?> _getImageBytes(ui.Image img) async {
    try {
      final ByteData? byteData =
          await img.toByteData(format: ui.ImageByteFormat.png);
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

  Future<ImageInfo?> captureScreenshot() {
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
      final pixelRatio =
          _getPixelRatio(srcWidth: srcWidth, srcHeight: srcHeight);

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
      Future(() async {
        final isSessionReplayActive =
            await _nativeCommunicator.isSessionReplayActive();

        // wait the UI to settle
        await SchedulerBinding.instance.endOfFrame;
        final image = await syncImage;
        if (!isSessionReplayActive || !image.isValidSize) {
          _snapshotManager.clear();
          image.dispose();
          completer.complete(null);
          return;
        }

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        // using png because its compressed, the native SDKs will decompress it
        // and transform to webp or jpeg if needed
        // https://github.com/brendan-duncan/image does not have webp encoding
        Uint8List? pngBytes = await _getImageBytes(image);
        if (pngBytes == null || pngBytes.isEmpty) {
          printIfDebug(
              'Error: Failed to convert image byte data to Uint8List.');
          recorder.endRecording().dispose();
          image.dispose();
          completer.complete(null);
          return;
        }

        if (const PHListEquality().equals(pngBytes, statusView.imageBytes)) {
          printIfDebug(
              'Debug: Snapshot is the same as the last one, nothing changed, do nothing.');
          recorder.endRecording().dispose();
          image.dispose();
          completer.complete(null);
          return;
        }

        statusView.imageBytes = pngBytes;

        try {
          canvas.drawImage(image, Offset.zero, Paint());
        } finally {
          image.dispose();
        }

        if (replayConfig.maskAllTexts || replayConfig.maskAllImages) {
          if (elementsDataWidgets != null && elementsDataWidgets.isNotEmpty) {
            _imageMaskPainter.drawMaskedImage(
                canvas, elementsDataWidgets, pixelRatio);
          }

          final picture = recorder.endRecording();

          try {
            final finalImage =
                await picture.toImage(srcWidth.toInt(), srcHeight.toInt());

            if (!finalImage.isValidSize) {
              finalImage.dispose();
              picture.dispose();
              completer.complete(null);
              return;
            }

            try {
              final maskedImagePngBytes = await _getImageBytes(finalImage);
              if (maskedImagePngBytes == null || maskedImagePngBytes.isEmpty) {
                finalImage.dispose();
                picture.dispose();
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
                maskedImagePngBytes,
              );
              _snapshotManager.updateStatus(renderObject,
                  shouldSendMetaEvent: shouldSendMetaEvent);
              completer.complete(imageInfo);
            } finally {
              finalImage.dispose();
            }
          } finally {
            picture.dispose();
          }
        } else {
          if (postHogWidgetWrapperElements != null &&
              postHogWidgetWrapperElements.isNotEmpty) {
            _imageMaskPainter.drawMaskedImageWrapper(
                canvas, postHogWidgetWrapperElements, pixelRatio);
          }

          final picture = recorder.endRecording();

          try {
            final finalImage =
                await picture.toImage(srcWidth.toInt(), srcHeight.toInt());

            if (!finalImage.isValidSize) {
              finalImage.dispose();
              picture.dispose();
              completer.complete(null);
              return;
            }

            try {
              final pngBytes = await _getImageBytes(finalImage);
              if (pngBytes == null || pngBytes.isEmpty) {
                finalImage.dispose();
                picture.dispose();
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
              _snapshotManager.updateStatus(renderObject,
                  shouldSendMetaEvent: shouldSendMetaEvent);
              completer.complete(imageInfo);
            } finally {
              finalImage.dispose();
            }
          } finally {
            picture.dispose();
          }
        }
      }).catchError((error) {
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
