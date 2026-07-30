import 'package:flutter/rendering.dart';

import '../element_parsers/element_data.dart';

/// Converts parsed widget elements to axis-aligned mask rects in the
/// PostHogWidget container's coordinate space.
List<Rect> containerMaskRects(List<ElementData> elements) {
  final rects = <Rect>[];
  for (final element in elements) {
    final transform = element.transform;
    final rect = transform != null
        ? MatrixUtils.transformRect(transform, element.rect)
        : element.rect;
    if (!rect.isFinite || rect.isEmpty) {
      continue;
    }
    // outset so capture-resolution rounding can't leave a sub-pixel glyph
    // edge visible at the mask border
    rects.add(rect.inflate(1.0));
  }
  return rects;
}
