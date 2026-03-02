import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';

/// Parser for [RenderEditable] objects (TextField input text).
///
/// Unlike [RenderParagraph] (used by Text widgets) where `size` and `paintBounds`
/// reflect the actual rendered text dimensions including font scaling, [RenderEditable]
/// only reports its layout bounds which can be very small (e.g., 1-2px height) when
/// used with `isDense: true` or constrained layouts like `Expanded`.
///
/// Example with ScreenUtil scaling:
/// - RenderParagraph: size = 28px (actual text height) ✓
/// - RenderEditable: size = 1.3px (layout bounds), preferredLineHeight = 39px (actual)
///
/// This parser uses [RenderEditable.preferredLineHeight] to determine the actual
/// rendered text height, ensuring the mask properly covers the visible text regardless
/// of the font scaling mechanism used (ScreenUtil, MediaQuery.textScaleFactor, etc.).
class RenderEditableParser extends ElementParser {
  @override
  ElementGeometry? buildElementData(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderEditable ||
        !renderObject.hasSize ||
        !renderObject.size.isValidSize) {
      return null;
    }

    // Use preferredLineHeight instead of size.height because RenderEditable's
    // layout height can be much smaller than the actual rendered text height
    final textHeight = renderObject.preferredLineHeight;
    final width = renderObject.size.width;

    // Account for multiline TextFields
    final lines = renderObject.maxLines ?? 1;
    final height = textHeight * lines;

    final localRect = Rect.fromLTWH(0, 0, width, height);
    final ancestor = PostHogMaskController.instance.containerKey.currentContext
        ?.findRenderObject();
    final transform = renderObject.getTransformTo(ancestor);

    return (rect: localRect, transform: transform);
  }
}
