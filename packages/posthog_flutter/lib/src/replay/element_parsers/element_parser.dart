import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';

class ElementParser {
  ElementParser();

  ElementData? relate(
    Element element,
    ElementData parentElementData,
  ) {
    final Rect? elementRect = buildElementRect(element, parentElementData.rect);
    if (elementRect == null) {
      return null;
    }

    final thisElementData = ElementData(
        type: element.widget.runtimeType.toString(),
        rect: elementRect,
        widget: element.widget);

    return thisElementData;
  }

  Rect? buildElementRect(Element element, Rect? parentRect) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.size.isValidSize) {
      final Offset offset = renderObject.localToGlobal(Offset.zero);
      return Rect.fromLTWH(
        offset.dx,
        offset.dy,
        renderObject.size.width,
        renderObject.size.height,
      );
    }
    return null;
  }
}
