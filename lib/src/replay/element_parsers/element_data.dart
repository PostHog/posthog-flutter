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

  List<Rect> extractNoMaskWidgetRects() {
    final rects = <Rect>[];
    _collectNoMaskWidgetRects(this, rects);
    return rects;
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

  void _collectNoMaskWidgetRects(ElementData element, List<Rect> rectList) {
    if (!rectList.contains(element.rect)) {
      if (element.type == "PostHogNoMaskWidget") {
        rectList.add(element.rect);
      }
    }

    if (element.children != null && element.children!.isNotEmpty) {
      for (var child in element.children!) {
        _collectNoMaskWidgetRects(child, rectList);
      }
    }
  }
}
