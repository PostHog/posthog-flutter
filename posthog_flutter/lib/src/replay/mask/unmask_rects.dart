import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';

Rect? axisAlignedUnmaskRect(Rect rect, Matrix4 transform) {
  final m = transform.storage;
  if (!rect.isFinite ||
      !m.every((value) => value.isFinite) ||
      m[2] != 0 ||
      m[3] != 0 ||
      m[6] != 0 ||
      m[7] != 0 ||
      m[8] != 0 ||
      m[9] != 0 ||
      m[10] != 1 ||
      m[11] != 0 ||
      m[14] != 0 ||
      m[15] != 1) {
    return null;
  }
  const tolerance = 1e-10;
  final diagonal = m[1].abs() <= tolerance && m[4].abs() <= tolerance;
  final swapped = m[0].abs() <= tolerance && m[5].abs() <= tolerance;
  if (!diagonal && !swapped) return null;
  // Inset away the rounding error of a nominally axis-aligned transform. An
  // exclusion must never grow beyond the actual unmasked quadrilateral.
  final inset = diagonal
      ? math.max(m[1].abs() * rect.width, m[4].abs() * rect.height)
      : math.max(m[0].abs() * rect.width, m[5].abs() * rect.height);
  final result = MatrixUtils.transformRect(transform, rect).deflate(inset);
  return result.isFinite ? result : null;
}

List<ElementData> subtractUnmaskRects(
    ElementData mask, Iterable<ElementData> unmasked) {
  if (mask.isSensitiveText) return [mask];
  final regions = unmasked.toList();
  if (regions.isEmpty) return [mask];
  final inverse = Matrix4.tryInvert(mask.transform ?? Matrix4.identity());
  if (inverse == null) return [mask];
  var parts = [mask.rect];
  for (final region in regions) {
    if (region.rect.isEmpty) continue;
    final relative = inverse.clone()
      ..multiply(region.transform ?? Matrix4.identity());
    final hole = axisAlignedUnmaskRect(region.rect, relative);
    if (hole == null || hole.isEmpty) continue;
    parts = parts.expand((part) => _subtract(part, hole)).toList();
  }
  if (parts.length == 1 && parts.single == mask.rect) return [mask];
  return parts
      .map((rect) => ElementData(
            rect: rect,
            type: mask.type,
            widget: mask.widget,
            transform: mask.transform,
          ))
      .toList();
}

Iterable<Rect> _subtract(Rect mask, Rect hole) {
  final cut = mask.intersect(hole);
  if (cut.isEmpty) return [mask];
  return [
    Rect.fromLTRB(mask.left, mask.top, mask.right, cut.top),
    Rect.fromLTRB(mask.left, cut.bottom, mask.right, mask.bottom),
    Rect.fromLTRB(mask.left, cut.top, cut.left, cut.bottom),
    Rect.fromLTRB(cut.right, cut.top, mask.right, cut.bottom),
  ].where((rect) => !rect.isEmpty);
}
