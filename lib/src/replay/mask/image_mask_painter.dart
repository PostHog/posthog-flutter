import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_widget.dart';

class ImageMaskPainter {
  void drawMaskedImage(
      Canvas canvas, List<ElementData> items, double pixelRatio) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var elementData in items) {
      paint.color = Colors.black;
      if (elementData.widget is PostHogMaskWidget) {
        paint.color = Colors.black;
      }

      // Apply the element's transform to draw the mask in the correct position/size
      // This handles ScreenUtil scaling, rotations, and other transforms
      if (elementData.transform != null) {
        canvas.save();

        // Scale the transform by pixelRatio for the output image
        final scaledTransform =
            Matrix4.diagonal3Values(pixelRatio, pixelRatio, 1.0)
              ..multiply(elementData.transform!);
        canvas.transform(scaledTransform.storage);

        // Draw the rect in local coordinates (transform positions it correctly)
        canvas.drawRect(elementData.rect, paint);
        canvas.restore();
      } else {
        // Fallback: no transform, use simple scaling
        final scaled = Rect.fromLTRB(
            elementData.rect.left * pixelRatio,
            elementData.rect.top * pixelRatio,
            elementData.rect.right * pixelRatio,
            elementData.rect.bottom * pixelRatio);
        canvas.drawRect(scaled, paint);
      }
    }
  }

  void drawMaskedImageWrapper(
      Canvas canvas, List<Rect> items, double pixelRatio) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (var rect in items) {
      paint.color = Colors.black;
      final scaled = Rect.fromLTRB(
          rect.left * pixelRatio,
          rect.top * pixelRatio,
          rect.right * pixelRatio,
          rect.bottom * pixelRatio);
      canvas.drawRect(scaled, paint);
    }
  }
}
