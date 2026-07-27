import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_widget.dart';

class ElementData {
  Rect rect;
  String type;
  List<ElementData>? children;
  Widget? widget;
  Matrix4? transform;

  ElementData({
    required this.rect,
    required this.type,
    this.children,
    this.widget,
    this.transform,
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

  /// Every node below the root is an element that already matched a masking
  /// rule, so the whole subtree is collected — a match can sit at any depth
  /// (a `ListTile` title nests `AnimatedDefaultTextStyle` → `DefaultTextStyle`
  /// → `Text` → `RichText`).
  List<ElementData> extractRects() {
    final rects = <ElementData>[];

    for (final child in children ?? const <ElementData>[]) {
      rects.add(child);
      rects.addAll(child.extractRects());
    }
    return rects;
  }

  void _collectMaskWidgetElements(
      ElementData element, List<ElementData> elements) {
    if (element.widget is PostHogMaskWidget) {
      elements.add(element);
    } else if (element.widget is TextField) {
      final textField = element.widget as TextField;
      if (textField.obscureText) {
        elements.add(element);
      }
    }

    final children = element.children;
    if (children != null && children.isNotEmpty) {
      for (var child in children) {
        _collectMaskWidgetElements(child, elements);
      }
    }
  }
}
