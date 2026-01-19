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
      // Use paintBounds to capture the actual painted area
      final Rect localRect = renderObject.paintBounds;

      // Get the full transform from this render object to the screen
      final Matrix4 transform = renderObject.getTransformTo(null);

      return ElementData(
        type: type,
        rect: localRect,
        transform: transform,
      );
    }
    return null;
  }
}
