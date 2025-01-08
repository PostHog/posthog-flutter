import 'package:flutter/material.dart';

class ElementData {
  List<ElementData>? children;
  Rect rect;
  String type;

  ElementData({
    this.children,
    required this.rect,
    required this.type,
  });

  void addChildren(ElementData elementData) {
    children ??= [];
    children?.add(elementData);
  }

  List<ElementData> extractRects([bool isRoot = true]) {
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
}
