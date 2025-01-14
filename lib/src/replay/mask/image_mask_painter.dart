import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';

class ImageMaskPainter {
  void drawMaskedImage(
    Canvas canvas,
    List<ElementData> items,
    double pixelRatio,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final element in items) {
      paint.color = _getColorForElement(element);

      final scaledRect = _scaleRect(element.rect, pixelRatio);

      canvas.drawRect(scaledRect, paint);
    }
  }

  void drawMaskedImageWrapper(
    Canvas canvas,
    List<Rect> items,
    double pixelRatio,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.pinkAccent;

    for (final rect in items) {
      final scaledRect = _scaleRect(rect, pixelRatio);
      canvas.drawRect(scaledRect, paint);
    }
  }

  Color _getColorForElement(ElementData element) {
    if (element.type == 'PostHogNoMaskWidget') {
      return Colors.pinkAccent;
    }
    return Colors.black;
  }

  Rect _scaleRect(Rect rect, double pixelRatio) {
    return Rect.fromLTRB(
      rect.left * pixelRatio,
      rect.top * pixelRatio,
      rect.right * pixelRatio,
      rect.bottom * pixelRatio,
    );
  }
}
