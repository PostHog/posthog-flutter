import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/screenshot/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/screenshot/native_communicator.dart';

class ScreenshotCapturer {
  /*
    * TEMPORARY FUNCTION FOR TESTING PURPOSES
    * This function sends a screenshot to PostHog.
    * It should be removed or refactored in the other version.
    */
  double getPixelRatio({
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

  ScreenshotCapturer();

  /*
    * TEMPORARY FUNCTION FOR TESTING PURPOSES
    * This function sends a screenshot to PostHog.
    * It should be removed or refactored in the other version.
    */
  Future<ui.Image?> captureScreenshot(NativeCommunicator nativeCommunicator) async {
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
      final pixelRatio = getPixelRatio(
        srcWidth: srcWidth,
        srcHeight: srcHeight,
      );

      final futureImage = renderObject.toImage(pixelRatio: pixelRatio);

      final wireframeTree = await PostHogMaskController.instance.getElementMaskTree();

      List<Rect> extractRects(ElementData node, [bool isRoot = true]) {
        List<Rect> rects = [];

        if (!isRoot && node.rect != null) {
          rects.add(node.rect);
        }

        // Traverse the children if any
        if (node.children != null && node.children!.isNotEmpty) {
          for (var child in node.children!) {
            rects.addAll(extractRects(child, false));
          }
        }
        return rects;
      }

      List<Rect> rects = extractRects(wireframeTree!);

      List<Map<String, double>> rectsData = rects.map((rect) {
        return {
          'left': rect.left,
          'top': rect.top,
          'right': rect.right,
          'bottom': rect.bottom,
        };
      }).toList();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final image = await futureImage;

      try {
        canvas.drawImage(image, Offset.zero, Paint());

        final rectPaint = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill;

        for (Rect rect in rects) {
          Rect scaledRect = Rect.fromLTRB(
            rect.left * pixelRatio,
            rect.top * pixelRatio,
            rect.right * pixelRatio,
            rect.bottom * pixelRatio,
          );

          canvas.drawRect(scaledRect, rectPaint);
        }
      } finally {
        image.dispose();
      }

      final picture = recorder.endRecording();
      print('Image dimensions: ${(srcWidth * pixelRatio).round()} x ${(srcHeight * pixelRatio).round()}');

      try {
        final originalImage = await picture.toImage(
          (srcWidth * pixelRatio).round(),
          (srcHeight * pixelRatio).round(),
        );

        ByteData? byteData = await originalImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          print('Error: Unable to convert image to byte data.');
          originalImage.dispose();
          return null;
        }

        Uint8List pngBytes = byteData.buffer.asUint8List();
        originalImage.dispose();

        await nativeCommunicator.sendImageAndRectsToNative(pngBytes, rectsData);
      } finally {}
    } catch (e) {
      print('Error capturing image: $e');
      return null;
    }
    return null;
  }
}
