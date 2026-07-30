import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/web/web_canvas_mask_geometry.dart';

void main() {
  ElementData element(Rect rect, {Matrix4? transform}) {
    return ElementData(rect: rect, type: 'Text', transform: transform);
  }

  test('outsets plain rects by one pixel', () {
    final rects = containerMaskRects([
      element(const Rect.fromLTWH(10, 20, 30, 40)),
    ]);

    expect(rects, [const Rect.fromLTWH(9, 19, 32, 42)]);
  });

  test('applies the element transform before outsetting', () {
    final rects = containerMaskRects([
      element(
        const Rect.fromLTWH(0, 0, 10, 10),
        transform: Matrix4.translationValues(100, 200, 0)
          ..scaleByDouble(2.0, 2.0, 2.0, 1.0),
      ),
    ]);

    expect(rects, [const Rect.fromLTWH(99, 199, 22, 22)]);
  });

  test('bounds rotated elements with an axis-aligned rect', () {
    final rects = containerMaskRects([
      element(
        const Rect.fromLTWH(0, 0, 10, 10),
        transform: Matrix4.rotationZ(0.5),
      ),
    ]);

    expect(rects, hasLength(1));
    final rect = rects.single;
    expect(
        rect.contains(MatrixUtils.transformPoint(
          Matrix4.rotationZ(0.5),
          const Offset(10, 10),
        )),
        isTrue);
    expect(rect.contains(const Offset(0, 0)), isTrue);
  });

  test('drops empty and non-finite rects before outsetting', () {
    final rects = containerMaskRects([
      element(Rect.zero.deflate(2)),
      element(Rect.zero),
      element(const Rect.fromLTWH(3, 4, 0, 10)),
      element(const Rect.fromLTWH(0, 0, double.infinity, 10)),
      element(const Rect.fromLTWH(0, 0, 5, 5)),
    ]);

    expect(rects, [const Rect.fromLTWH(-1, -1, 7, 7)]);
  });
}
