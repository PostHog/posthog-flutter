import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

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

    // Handle TextField and TextFormField masking
    // Only mask at widget level for obscureText fields when maskAllTexts is false
    // When maskAllTexts is true, RenderEditable detection will handle it with better bounds
    if (element.widget is TextField || element.widget is TextFormField) {
      final config = Posthog().config?.sessionReplayConfig;
      final maskAllTexts = config?.maskAllTexts ?? true;

      var isObscured = false;
      if (element.widget is TextField) {
        isObscured = (element.widget as TextField).obscureText;
      }

      // Note: TextFormField obscureText is handled differently in Flutter.
      // TextFormField creates an internal TextField, but the obscureText property
      // is not directly accessible on the TextFormField widget itself.
      // For TextFormField, we rely on the maskAllTexts configuration.
      // Otherwise, let RenderEditable handle it (it has better bounds via preferredLineHeight)
      final shouldMask = !maskAllTexts && isObscured;

      if (shouldMask) {
        final elementData = _elementParser.relate(element, activeElementData);

        if (elementData != null) {
          activeElementData.addChildren(elementData);
          return elementData;
        }
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

    if (element.renderObject is RenderParagraph ||
        element.renderObject is RenderEditable) {
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
