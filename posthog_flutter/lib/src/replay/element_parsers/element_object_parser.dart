import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/render_editable_parser.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/mask/sensitive_text_input.dart';

class ElementObjectParser {
  final ElementParser _elementParser = ElementParser();
  final RenderEditableParser _renderEditableParser = RenderEditableParser();

  ElementData? relateRenderObject(
    ElementData activeElementData,
    Element element, {
    bool unmask = false,
    bool sensitiveText = false,
  }) {
    if (element.widget is PostHogMaskWidget ||
        isSensitiveTextInput(element.widget)) {
      final elementData = _elementParser.relate(element);

      if (elementData != null) {
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

    // Dense/scaled inputs can paint beyond their widget bounds. Preserve the
    // RenderEditable mask as part of the sensitivity floor, even when unmasked.
    if (sensitiveText &&
        element is RenderObjectElement &&
        element.renderObject is RenderEditable) {
      final elementData = _renderEditableParser.relate(element);
      if (elementData != null) {
        elementData.isSensitiveText = true;
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

    if (unmask) return null;

    if (element.widget is Text) {
      final config = Posthog().config?.sessionReplayConfig;
      final maskAllTexts = config?.maskAllTexts ?? true;

      if (maskAllTexts) {
        final elementData = _elementParser.relate(element);

        if (elementData != null) {
          activeElementData.addChildren(elementData);
          return elementData;
        }
      }
    }

    // Component elements can forward a descendant's render object before an
    // intervening unmask widget has been visited. Match only its owning element.
    if (element is! RenderObjectElement) return null;

    if (element.renderObject is RenderImage) {
      final dataType = element.renderObject.runtimeType.toString();

      final parser = PostHogMaskController.instance.parsers[dataType];
      if (parser != null) {
        final elementData = parser.relate(element);

        if (elementData != null) {
          activeElementData.addChildren(elementData);
          return elementData;
        }
      }
    }

    if (element.renderObject is RenderParagraph ||
        element.renderObject is RenderEditable) {
      final dataType = element.renderObject.runtimeType.toString();

      final parser = PostHogMaskController.instance.parsers[dataType];
      if (parser != null) {
        final elementData = parser.relate(element);

        if (elementData != null) {
          activeElementData.addChildren(elementData);
          return elementData;
        }
      }
    }

    return null;
  }
}
