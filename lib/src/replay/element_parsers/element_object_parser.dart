import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_widget.dart';

class ElementObjectParser {
  final ElementParser _elementParser = ElementParser();

  ElementData? relateRenderObject(
    ElementData activeElementData,
    Element element,
  ) {
    if (element.widget is PostHogMaskWidget) {
      final elementData = _elementParser.relate(element, activeElementData);

      if (elementData != null) {
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

    if (element.widget is Text) {
      final elementData = _elementParser.relate(element, activeElementData);

      if (elementData != null) {
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

    if (element.renderObject is RenderImage) {
      final dataType = element.renderObject.runtimeType.toString();

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
