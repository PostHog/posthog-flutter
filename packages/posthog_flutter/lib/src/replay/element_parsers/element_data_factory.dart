import 'package:flutter/cupertino.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';

class ElementDataFactory {
  /// Creates an ElementData object from an Element
  ElementData? createFromElement(Element element, String type) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.size.isValidSize) {
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
