import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';

class ImageMaskPainter {
  void drawMaskedImage(
    Canvas canvas,
    List<ElementData> items,
    double pixelRatio,
  ) {
    final downscaled = pixelRatio < 1.0;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black
      ..isAntiAlias = !downscaled;

    for (var elementData in items) {
      // Apply the element's transform to draw the mask in the correct position/size
      // This handles ScreenUtil scaling, rotations, and other transforms
      final transform = elementData.transform;
      if (downscaled) {
        // Round screen-space bounds outward so a partially covered output
        // pixel cannot retain sensitive content after downsampling.
        final scaledTransform = Matrix4.diagonal3Values(
          pixelRatio,
          pixelRatio,
          1.0,
        );
        if (transform != null) {
          // A perspective horizon can make a four-corner hull smaller than
          // the painted region. Let the capturer drop an unsafe frame.
          final m = transform.storage;
          if (m[3] != 0 || m[7] != 0) {
            final rect = elementData.rect;
            final w = [
              for (final point in [
                rect.topLeft,
                rect.topRight,
                rect.bottomLeft,
                rect.bottomRight,
              ])
                m[3] * point.dx + m[7] * point.dy + m[15],
            ];
            if (!w.every((value) => value > 0) &&
                !w.every((value) => value < 0)) {
              throw StateError('Cannot safely scale a perspective mask.');
            }
          }
          scaledTransform.multiply(transform);
        }
        final bounds =
            MatrixUtils.transformRect(scaledTransform, elementData.rect);
        if (!bounds.isFinite) {
          throw StateError('Cannot safely scale non-finite mask bounds.');
        }
        canvas.drawRect(
          Rect.fromLTRB(
            bounds.left.floorToDouble(),
            bounds.top.floorToDouble(),
            bounds.right.ceilToDouble(),
            bounds.bottom.ceilToDouble(),
          ),
          paint,
        );
        continue;
      }
      if (transform != null) {
        canvas.save();

        // Scale the transform by pixelRatio for the output image
        final scaledTransform = Matrix4.diagonal3Values(
          pixelRatio,
          pixelRatio,
          1.0,
        )..multiply(transform);
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
          elementData.rect.bottom * pixelRatio,
        );
        canvas.drawRect(scaled, paint);
      }
    }
  }
}
