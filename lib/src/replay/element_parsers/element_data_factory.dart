import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';

class ElementDataFactory {
  /// Creates an ElementData object from an Element
  ElementData? createFromElement(Element element, String type) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize) {
      final offset = renderObject.localToGlobal(Offset.zero);
      return ElementData(
        type: type,
        rect: Rect.fromLTWH(
          offset.dx,
          offset.dy,
          renderObject.size.width,
          renderObject.size.height,
        ),
      );
    }
    return null;
  }
}
