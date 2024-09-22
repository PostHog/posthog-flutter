import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ScreenshotCapturer {
  final GlobalKey screenshotKey;

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

  ScreenshotCapturer(this.screenshotKey);

  Future<ui.Image?> captureScreenshot() async {
    final context = screenshotKey.currentContext;
    if (context == null) {
      print('Error: screenshotKey has no context.');
      return null;
    }

    final renderObject = context.findRenderObject() as RenderRepaintBoundary?;
    if (renderObject == null) {
      print('Error: Unable to find RenderRepaintBoundary.');
      return null;
    }

    final srcWidth = renderObject.size.width;
    final srcHeight = renderObject.size.height;

    try {
      final pixelRatio =
          getPixelRatio(srcWidth: srcWidth, srcHeight: srcHeight);
      return await renderObject.toImage(pixelRatio: pixelRatio);
    } catch (e) {
      print('Error capturing image: $e');
      return null;
    }
  }
}
