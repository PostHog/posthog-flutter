import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ImageMasker {
  Future<ui.Image> applyMasks(
      ui.Image originalImage, List<Rect> maskedAreas) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint();
    canvas.drawImage(originalImage, Offset.zero, paint);

    final maskPaint = Paint()..color = Colors.black;
    for (final rect in maskedAreas) {
      canvas.drawRect(rect, maskPaint);
    }

    final picture = recorder.endRecording();
    final maskedImage = await picture.toImage(
      originalImage.width,
      originalImage.height,
    );

    return maskedImage;
  }
}
