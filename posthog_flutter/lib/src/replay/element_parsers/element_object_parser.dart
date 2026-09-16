import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/render_editable_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/text_mask_policy_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/unmask_element_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parsers_const.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/mask/sensitive_text_input.dart';

class ElementObjectParser {
  final ElementParser _elementParser = ElementParser();
  final RenderEditableParser _renderEditableParser = RenderEditableParser();
  final UnmaskElementParser _unmaskParser = UnmaskElementParser();
  final TextMaskPolicyParser _textMaskPolicyParser = TextMaskPolicyParser();

  ElementData? relateRenderObject(
    ElementData activeElementData,
    Element element, {
    bool unmask = false,
    bool sensitiveText = false,
  }) {
    if (element.widget is PostHogUnmaskWidget) {
      final elementData = _unmaskParser.relate(element);
      if (elementData != null) {
        elementData.isUnmask = true;
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

    final isSensitiveText = isSensitiveTextInput(element.widget);
    if ((!unmask && element.widget is PostHogMaskWidget) || isSensitiveText) {
      final elementData = _elementParser.relate(element);

      if (elementData != null) {
        elementData.isSensitiveText = isSensitiveText;
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

    final replayConfig = Posthog().config?.sessionReplayConfig;
    final textMaskPolicy = replayConfig?.textMaskPolicy;

    // With a policy set, the owning render object element below decides.
    if (element.widget is Text && textMaskPolicy == null) {
      final maskAllTexts = replayConfig?.maskAllTexts ?? true;

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

    final renderObject = element.renderObject;
    if (renderObject is RenderCustomPaint &&
        (renderObject.painter != null ||
            renderObject.foregroundPainter != null)) {
      // Only exempt the framework painter itself; subclasses can paint content.
      if (renderObject.painter == null &&
          renderObject.foregroundPainter.runtimeType == ScrollbarPainter) {
        return null;
      }
      // Canvas commands cannot be inspected for sensitive text or images.
      final parser = PostHogMaskController.instance
          .parsers[ElementParsersConst.getRuntimeType<RenderCustomPaint>()];
      if (parser != null) {
        final elementData = parser.relate(element);
        if (elementData == null) {
          // A zero-sized painter can paint outside its ancestors, so guessing
          // an ancestor's bounds is unsafe. The caller drops the frame.
          throw StateError('Cannot determine CustomPaint mask bounds.');
        }
        activeElementData.addChildren(elementData);
        return elementData;
      }
    }

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
      if (textMaskPolicy != null) {
        final masks = _textMaskPolicyParser.relate(element, textMaskPolicy);
        if (masks != null) {
          for (final mask in masks) {
            activeElementData.addChildren(mask);
          }
          // A RichText can carry a PostHogMaskWidget/PostHogUnmaskWidget of
          // its own inside a WidgetSpan. When the policy produced exactly
          // one rect for this node, descend into it so that structure
          // attaches as its descendant and subtractUnmaskRects can see it.
          // More than one rect has no single box for it to nest under, but
          // none is needed: a WidgetSpan is its own inline slot and can't
          // overlap a sibling text glyph run.
          return masks.length == 1 ? masks.single : null;
        }
      }

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
