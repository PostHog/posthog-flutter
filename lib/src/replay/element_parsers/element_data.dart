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
    children!.add(elementData);
  }

  //TODO: THIS MAY BE BETTER
  List<Rect> extractRects([bool isRoot = true]) {
    List<Rect> rects = [];

    if (!isRoot) {
      rects.add(rect);
    }

    if (children != null) {
      for (var child in children!) {
        if (child.children == null) {
          rects.add(child.rect);
          continue;
        } else if (child.children!.length > 1) {
          for (var grandChild in child.children!) {
            rects.add(grandChild.rect);
          }
        } else {
          rects.add(child.rect);
        }
      }
    }
    return rects;
  }
}
