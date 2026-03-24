// ignore_for_file: avoid_dynamic_calls

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

  List<ElementData> extractRects({bool isRoot = true}) {
    List<ElementData> rects = [];

    if (children != null) {
      for (var child in children ?? []) {
        if (child.children == null) {
          rects.add(child);
          continue;
        } else if ((child.children?.length ?? 0) > 1) {
          for (var grandChild in child.children ?? []) {
            rects.add(grandChild);
          }
        } else {
          rects.add(child);
        }
      }
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
