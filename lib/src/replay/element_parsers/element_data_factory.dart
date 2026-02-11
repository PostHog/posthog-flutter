import 'package:flutter/cupertino.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
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

      // Get the transform relative to the screenshot container (RepaintBoundary)
      final ancestor = PostHogMaskController
          .instance.containerKey.currentContext
          ?.findRenderObject();
      final Matrix4 transform = renderObject.getTransformTo(ancestor);

      return ElementData(
        type: type,
        rect: localRect,
        transform: transform,
      );
    }
    return null;
  }
}
