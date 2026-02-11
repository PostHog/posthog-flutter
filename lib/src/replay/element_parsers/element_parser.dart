import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';

class ElementParser {
  ElementParser();

  ElementData? relate(
    Element element,
    ElementData parentElementData,
  ) {
    final result = buildElementData(element);
    if (result == null) {
      return null;
    }

    final thisElementData = ElementData(
        type: element.widget.runtimeType.toString(),
        rect: result.rect,
        widget: element.widget,
        transform: result.transform);

    return thisElementData;
  }

  /// Returns a record containing the local rect and transform for the element
  ({Rect rect, Matrix4 transform})? buildElementData(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.size.isValidSize) {
      // Use paintBounds to capture the actual painted area
      // This is important for text with ScreenUtil scaling where the painted
      // text can be larger than the logical layout bounds
      final Rect localRect = renderObject.paintBounds;

      // Get the transform relative to the screenshot container (RepaintBoundary)
      // Using the container's RenderObject as ancestor ensures transforms are in
      // the screenshot's coordinate space, not absolute screen coordinates
      final ancestor = PostHogMaskController
          .instance.containerKey.currentContext
          ?.findRenderObject();
      final Matrix4 transform = renderObject.getTransformTo(ancestor);

      return (rect: localRect, transform: transform);
    }
    return null;
  }
}
