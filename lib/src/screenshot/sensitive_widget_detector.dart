import 'package:flutter/material.dart';

class SensitiveWidgetDetector {
  final bool maskAllTextInputs;
  final bool maskAllImages;

  SensitiveWidgetDetector({
    required this.maskAllTextInputs,
    required this.maskAllImages,
  });

  List<Rect> findSensitiveAreas(Element rootElement) {
    final List<Rect> sensitiveAreas = [];
    _traverseElementTree(rootElement, sensitiveAreas);
    return sensitiveAreas;
  }

  void _traverseElementTree(Element element, List<Rect> sensitiveAreas) {
    final widget = element.widget;
    final renderObject = element.renderObject;

    if (_isSensitiveWidget(widget)) {
      if (renderObject is RenderBox) {
        final rect = _getWidgetBoundingBox(renderObject);
        if (rect != null) {
          sensitiveAreas.add(rect);
        }
      }
    }

    element.visitChildElements((child) {
      _traverseElementTree(child, sensitiveAreas);
    });
  }

  bool _isSensitiveWidget(Widget widget) {
    if (maskAllTextInputs && widget is TextField) {
      return true;
    }
    if (maskAllImages && widget is Image) {
      return true;
    }
    return false;
  }

  Rect? _getWidgetBoundingBox(RenderBox renderBox) {
    try {
      final offset = renderBox.localToGlobal(Offset.zero);
      return Rect.fromLTWH(
        offset.dx,
        offset.dy,
        renderBox.size.width,
        renderBox.size.height,
      );
    } catch (e) {
      print('Error when calculating the bounding box: $e');
      return null;
    }
  }
}
