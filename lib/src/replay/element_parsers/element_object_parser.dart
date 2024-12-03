import 'package:flutter/cupertino.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

class ElementObjectParser {
  ElementData? relateRenderObject(
    ElementData activeElementData,
    Element element,
  ) {
    if (element.renderObject is RenderBox) {
      final String dataType = element.renderObject.runtimeType.toString();

      final parser = PostHogMaskController.instance.parsers[dataType];
      if (parser != null) {
        final elementData = parser.relate(element, activeElementData);

        if (elementData != null) {
          activeElementData.addChildren(elementData);
          return elementData;
        }
      }
    }
    return null;
  }
}
