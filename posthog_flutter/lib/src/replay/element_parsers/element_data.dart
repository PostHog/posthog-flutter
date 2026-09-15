import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_widget.dart';
import 'package:posthog_flutter/src/replay/mask/unmask_rects.dart';

class ElementData {
  Rect rect;
  String type;
  List<ElementData>? children;
  Widget? widget;
  Matrix4? transform;
  bool isSensitiveText;
  bool isUnmask;

  ElementData({
    required this.rect,
    required this.type,
    this.children,
    this.widget,
    this.transform,
    this.isSensitiveText = false,
    this.isUnmask = false,
  });

  void addChildren(ElementData elementData) {
    children ??= [];
    children?.add(elementData);
  }

  List<ElementData> extractMaskWidgetRects() {
    final elements = <ElementData>[];
    _collectMaskWidgetElements(this, elements);
    return elements;
  }

  /// Collect every matched mask at any depth, excluding visible descendant
  /// unmask regions from non-sensitive masks. Unmask markers themselves are
  /// never emitted as masks.
  List<ElementData> extractRects() {
    final rects = <ElementData>[];

    for (final child in children ?? const <ElementData>[]) {
      if (!child.isUnmask) {
        rects.addAll(subtractUnmaskRects(child, child._unmaskedDescendants()));
      }
      rects.addAll(child.extractRects());
    }
    return rects;
  }

  Iterable<ElementData> _unmaskedDescendants() sync* {
    for (final child in children ?? const <ElementData>[]) {
      if (child.isUnmask) yield child;
      yield* child._unmaskedDescendants();
    }
  }

  void _collectMaskWidgetElements(
      ElementData element, List<ElementData> elements) {
    if (element.widget is PostHogMaskWidget || element.isSensitiveText) {
      elements
          .addAll(subtractUnmaskRects(element, element._unmaskedDescendants()));
    }

    final children = element.children;
    if (children != null && children.isNotEmpty) {
      for (var child in children) {
        _collectMaskWidgetElements(child, elements);
      }
    }
  }
}
