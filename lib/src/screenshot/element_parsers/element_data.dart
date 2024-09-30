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
}
