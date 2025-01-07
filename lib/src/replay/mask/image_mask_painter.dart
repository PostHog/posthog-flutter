import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ImageMaskPainter {
  Future<ui.Image> drawMaskedImage(
      ui.Image image, List<Rect> rects, double pixelRatio) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    canvas.drawImage(image, Offset.zero, paint);

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

    final picture = recorder.endRecording();

    final maskedImage = await picture.toImage(
      (image.width * pixelRatio).round(),
      (image.height * pixelRatio).round(),
    );
    return maskedImage;
  }
}
