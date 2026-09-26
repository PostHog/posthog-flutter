import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/unmask_rects.dart';

ElementData region(Rect rect, {Matrix4? transform, bool sensitive = false}) =>
    ElementData(
        rect: rect,
        type: 'test',
        transform: transform,
        isSensitiveText: sensitive);

void main() {
  const outer = Rect.fromLTWH(0, 0, 100, 100);
  const inner = Rect.fromLTWH(20, 20, 40, 40);

  test('subtracts only the hole and retains the rest of the mask', () {
    final parts = subtractUnmaskRects(region(outer), [region(inner)]);
    expect(parts, hasLength(4));
    expect(parts.any((part) => part.rect.overlaps(inner)), isFalse);
    expect(
        parts.fold<double>(
            0, (area, part) => area + part.rect.width * part.rect.height),
        8400);
  });

  test('handles overlapping holes and a hole crossing a mask edge', () {
    final holes = [inner, const Rect.fromLTWH(40, 40, 80, 80)];
    final parts = subtractUnmaskRects(region(outer), holes.map(region));
    for (var y = 0.5; y < 100; y++) {
      for (var x = 0.5; x < 100; x++) {
        final point = Offset(x, y);
        expect(parts.any((part) => part.rect.contains(point)),
            !holes.any((hole) => hole.contains(point)));
      }
    }
  });

  void expectOnlyInnerUnmasked(List<ElementData> parts) {
    expect(parts, isNotEmpty);
    for (var y = 0.5; y < 100; y++) {
      for (var x = 0.5; x < 100; x++) {
        final point = Offset(x, y);
        expect(parts.any((part) => part.rect.contains(point)),
            !inner.contains(point));
      }
    }
  }

  test('uses the mask coordinate space under shared rotation and scaling', () {
    final transform = Matrix4.identity()
      ..rotateZ(math.pi / 4)
      ..multiply(Matrix4.diagonal3Values(2, 2, 1));
    final parts = subtractUnmaskRects(region(outer, transform: transform),
        [region(inner, transform: transform)]);
    expectOnlyInnerUnmasked(parts);
    expect(parts.every((part) => identical(part.transform, transform)), isTrue);
  });

  test('resolves translated and mirrored holes', () {
    final transform = Matrix4.identity()
      ..setTranslationRaw(60, 20, 0)
      ..multiply(Matrix4.diagonal3Values(-1, 1, 1));
    final parts = subtractUnmaskRects(region(outer),
        [region(const Rect.fromLTWH(0, 0, 40, 40), transform: transform)]);
    expectOnlyInnerUnmasked(parts);
  });

  test('never subtracts from a sensitive input mask', () {
    final mask = region(outer, sensitive: true);
    expect(subtractUnmaskRects(mask, [region(outer)]), [mask]);
  });

  test('retains masks for singular, rotated, and perspective exclusions', () {
    for (final transform in [
      Matrix4.identity()..rotateZ(math.pi / 4),
      Matrix4.identity()..setEntry(3, 0, 0.1),
    ]) {
      final mask = region(outer);
      expect(subtractUnmaskRects(mask, [region(inner, transform: transform)]),
          [mask]);
    }
    final singular = region(outer, transform: Matrix4.zero());
    expect(subtractUnmaskRects(singular, [region(inner)]), [singular]);
  });
}
