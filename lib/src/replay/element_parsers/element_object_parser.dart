import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_nomask_widget.dart';

class ElementObjectParser {
  ElementData? relateRenderObject(
    ElementData activeElementData,
    Element element,
  ) {
    if (element.widget is PostHogNoMaskWidget) {
      final elementData = ElementParser().relate(element, activeElementData);

      if (elementData != null) {
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

    if (element.widget is Text) {
      final elementData = ElementParser().relate(element, activeElementData);

      if (elementData != null) {
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

    if (element.renderObject is RenderImage) {
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

    // THIS WAY IN THE FUTURE WE CAN MOUNTED FULL WIREFRAME MORE EASILY
    /*
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
     */

    return null;
  }
}
