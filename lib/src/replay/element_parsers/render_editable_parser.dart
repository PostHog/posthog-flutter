import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
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
  ({Rect rect, Matrix4 transform})? buildElementData(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderEditable ||
        !renderObject.hasSize ||
        !renderObject.size.isValidSize) {
      return null;
    }

    // Use preferredLineHeight instead of size.height because RenderEditable's
    // layout height can be much smaller than the actual rendered text height
    final double textHeight = renderObject.preferredLineHeight;
    final double width = renderObject.size.width;

    // Account for multiline TextFields
    final int lines = renderObject.maxLines ?? 1;
    final double height = textHeight * lines;

    final Rect localRect = Rect.fromLTWH(0, 0, width, height);
    final Matrix4 transform = renderObject.getTransformTo(null);

    return (rect: localRect, transform: transform);
  }
}
