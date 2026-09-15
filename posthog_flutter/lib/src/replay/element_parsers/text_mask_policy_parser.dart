import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/element_parsers/render_editable_parser.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_text_mask.dart';
import 'package:posthog_flutter/src/replay/mask/unmask_rects.dart';
import 'package:posthog_flutter/src/util/logging.dart';

/// Applies a [PostHogTextMaskPolicy] to one text node and turns its decision
/// into mask rects.
///
/// Handles the render object a plain `Text` or `RichText` produces
/// ([RenderParagraph]) and the one a text input produces ([RenderEditable]).
/// The policy sees the node's rendered string with semantics labels excluded,
/// so its character offsets line up with the laid-out text. A range that
/// wraps yields one rect per line.
///
/// Fails closed: a policy that throws, or returns a range outside the text,
/// masks the whole node.
class TextMaskPolicyParser {
  final ElementParser _paragraphParser = ElementParser();
  final RenderEditableParser _editableParser = RenderEditableParser();

  /// Mask rects for [element] under [policy], or null when [element] is not a
  /// text node this parser handles.
  List<ElementData>? relate(Element element, PostHogTextMaskPolicy policy) {
    final RenderBox renderObject;
    final String text;
    final ElementGeometry? geometry;
    switch (element.renderObject) {
      case final RenderParagraph paragraph:
        renderObject = paragraph;
        text = paragraph.text.toPlainText(includeSemanticsLabels: false);
        geometry = _paragraphParser.buildElementData(element);
      case final RenderEditable editable:
        renderObject = editable;
        text = editable.text?.toPlainText(includeSemanticsLabels: false) ?? '';
        geometry = _editableParser.buildElementData(element);
      default:
        return null;
    }
    if (geometry == null) return const [];

    final PostHogTextMask decision;
    try {
      decision = policy(text);
    } catch (e) {
      printIfDebug(
          '[PostHog] textMaskPolicy threw, masking the whole node: $e');
      return _rects(element, geometry, [geometry.rect]);
    }

    final whole = geometry.rect;
    final rects = switch (decision) {
      PostHogTextMaskAll() => [whole],
      PostHogTextMaskNone() => const <Rect>[],
      PostHogTextMaskOnly(:final ranges) =>
        _rangeRects(ranges, false, text, renderObject, whole),
      PostHogTextMaskExcept(:final ranges) =>
        _rangeRects(ranges, true, text, renderObject, whole),
    };
    return _rects(element, geometry, rects);
  }

  List<Rect> _rangeRects(
    Iterable<TextRange> ranges,
    bool except,
    String text,
    RenderBox renderObject,
    Rect whole,
  ) {
    final boxes = <Rect>[];
    for (final range in ranges) {
      if (range.start < 0 ||
          range.end > text.length ||
          !range.isNormalized ||
          range.isCollapsed) {
        printIfDebug(
          '[PostHog] textMaskPolicy returned a range outside the text, '
          'masking the whole node instead.',
        );
        return [whole];
      }
      final List<TextBox> lineBoxes;
      try {
        lineBoxes = _boxesForRange(renderObject, range);
      } catch (e) {
        printIfDebug(
          '[PostHog] textMaskPolicy range failed to lay out, '
          'masking the whole node: $e',
        );
        return [whole];
      }
      for (final box in lineBoxes) {
        final rect = box.toRect().intersect(whole);
        if (!rect.isEmpty) boxes.add(rect);
      }
    }
    if (!except) return boxes;
    var parts = [whole];
    for (final box in boxes) {
      parts = parts.expand((part) => subtractRect(part, box)).toList();
    }
    return parts;
  }

  // Full line height rather than tight glyph bounds, so an `except` decision
  // leaves no slivers of the line above and below the revealed glyphs.
  List<TextBox> _boxesForRange(RenderBox renderObject, TextRange range) {
    final selection =
        TextSelection(baseOffset: range.start, extentOffset: range.end);
    if (renderObject is RenderParagraph) {
      return renderObject.getBoxesForSelection(
        selection,
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
    }
    if (renderObject is RenderEditable) {
      return [
        for (final box in renderObject.getBoxesForSelection(selection))
          _fullLineHeight(renderObject, box),
      ];
    }
    return const [];
  }

  // RenderEditable only offers tight boxes; grow each one to the caret rect
  // of its line, which spans the line height.
  TextBox _fullLineHeight(RenderEditable editable, TextBox box) {
    final position = editable.getPositionForPoint(
      editable.localToGlobal(Offset(box.left, (box.top + box.bottom) / 2)),
    );
    final line = editable.getLocalRectForCaret(position);
    return TextBox.fromLTRBD(
      box.left,
      math.min(box.top, line.top),
      box.right,
      math.max(box.bottom, line.bottom),
      box.direction,
    );
  }

  List<ElementData> _rects(
    Element element,
    ElementGeometry geometry,
    List<Rect> rects,
  ) {
    return [
      for (final rect in rects)
        ElementData(
          type: element.widget.runtimeType.toString(),
          rect: rect,
          widget: element.widget,
          transform: geometry.transform,
        ),
    ];
  }
}
