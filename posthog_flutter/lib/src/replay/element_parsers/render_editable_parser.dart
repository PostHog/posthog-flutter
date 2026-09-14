import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';

/// Parser for [RenderEditable] objects (TextField input text).
///
/// The mask height is the larger of two bounds, because neither is enough on
/// its own:
///
/// - `size.height` is the layout height. Unlike [RenderParagraph], whose `size`
///   reflects the rendered text, a [RenderEditable] can be laid out far smaller
///   than the text it paints when the field is dense or constrained
///   (`isDense: true`, `Expanded`, ScreenUtil scaling): 1.3px tall with a
///   `preferredLineHeight` of 39px has been measured.
/// - `preferredLineHeight * maxLines` estimates the painted text from the line
///   count, but `maxLines` is null for an auto-growing field (`maxLines: null`,
///   `expands: true`), whose real height grows with its content. Treated as a
///   single line, only the first line of such a field would be masked.
class RenderEditableParser extends ElementParser {
  @override
  ElementGeometry? buildElementData(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderEditable ||
        !renderObject.hasSize ||
        !renderObject.size.isValidSize) {
      return null;
    }

    final width = renderObject.size.width;
    final lines = renderObject.maxLines ?? 1;
    final height = math.max(
      renderObject.size.height,
      renderObject.preferredLineHeight * lines,
    );

    final localRect = Rect.fromLTWH(0, 0, width, height);
    final ancestor = PostHogMaskController.instance.containerKey.currentContext
        ?.findRenderObject();
    final transform = renderObject.getTransformTo(ancestor);

    return (rect: localRect, transform: transform);
  }
}
