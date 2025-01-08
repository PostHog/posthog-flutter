import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';

class ImageMaskPainter {
  void drawMaskedImage(
      Canvas canvas, List<ElementData> items, double pixelRatio) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var elementData in items) {
      paint.color = Colors.black;
      final scaled = Rect.fromLTRB(
          elementData.rect.left * pixelRatio,
          elementData.rect.top * pixelRatio,
          elementData.rect.right * pixelRatio,
          elementData.rect.bottom * pixelRatio);
      canvas.drawRect(scaled, paint);
    }
  }
}
