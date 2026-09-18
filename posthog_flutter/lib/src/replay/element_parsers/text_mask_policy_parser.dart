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
/// so its character offsets line up with the laid-out text, plus the widget
/// itself. A range that wraps yields one rect per line.
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
    final Widget policyWidget;
    var hasWidgetSpan = false;
    switch (element.renderObject) {
      case final RenderParagraph paragraph:
        renderObject = paragraph;
        text = paragraph.text.toPlainText(includeSemanticsLabels: false);
        geometry = _paragraphParser.buildElementData(element);
        // Text builds RichText directly, so element.widget already is the
        // widget doing the rendering — and it's public and useful either way
        // (its own style, its InlineSpan) whether an app wrote Text or
        // RichText itself.
        policyWidget = element.widget;
        hasWidgetSpan = _containsWidgetSpan(paragraph.text);
      case final RenderEditable editable:
        renderObject = editable;
        text = editable.text?.toPlainText(includeSemanticsLabels: false) ?? '';
        geometry = _editableParser.buildElementData(element);
        // Unlike RichText, the widget that actually owns a RenderEditable is
        // Flutter's private `_Editable` — a type this package can't even
        // name, let alone anything an app's policy could usefully inspect.
        // Its own EditableText ancestor is what carries the properties a
        // policy would actually want (obscureText, readOnly, ...), so find
        // that instead of handing back something nobody can use.
        policyWidget = _nearestEditableText(element) ?? element.widget;
      default:
        return null;
    }
    if (geometry == null) return const [];

    final PostHogTextMask decision;
    try {
      decision = policy(text, policyWidget);
    } catch (e) {
      printIfDebug(
          '[PostHog] textMaskPolicy threw, masking the whole node: $e');
      return _rects(policyWidget, geometry, [geometry.rect]);
    }

    final whole = geometry.rect;
    List<Rect> rects;
    try {
      rects = switch (decision) {
        PostHogTextMaskAll() => [whole],
        PostHogTextMaskNone() => const <Rect>[],
        PostHogTextMaskOnly(:final ranges) =>
          _rangeRects(ranges, false, text, renderObject, whole),
        PostHogTextMaskExcept(:final ranges) =>
          _rangeRects(ranges, true, text, renderObject, whole),
      };
    } catch (e) {
      // `ranges` is caller-supplied and can be lazy (the shipped presets
      // themselves return a `.map()`), so a range that throws when it's
      // actually evaluated — not when the policy returns it — must fail
      // closed too, the same as a policy that throws outright.
      printIfDebug('[PostHog] textMaskPolicy\'s ranges threw while iterating, '
          'masking the whole node: $e');
      return _rects(policyWidget, geometry, [whole]);
    }
    if (hasWidgetSpan && rects.length != 1) {
      // A WidgetSpan can carry its own PostHogMaskWidget/PostHogUnmaskWidget,
      // and `except`'s rects in particular are the complement of the whole
      // node — full-width bands that, unlike a single glyph-range match,
      // reach across the WidgetSpan's inline slot regardless of how many of
      // them there are. With more than one rect there's no single box for
      // nested structure to attach beneath (see the caller), so fail closed
      // to the one case that already works instead of risking exactly the
      // WidgetSpan precedence bug this exists to prevent.
      rects = [whole];
    }
    return _rects(policyWidget, geometry, rects);
  }

  bool _containsWidgetSpan(InlineSpan span) {
    if (span is WidgetSpan) return true;
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (_containsWidgetSpan(child)) return true;
      }
    }
    return false;
  }

  /// The nearest [EditableText] above [element], or null if none is found —
  /// which shouldn't happen for a real [RenderEditable], but this is replay
  /// code, so it fails soft rather than crashing capture.
  EditableText? _nearestEditableText(Element element) {
    EditableText? found;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is EditableText) {
        found = widget;
        return false;
      }
      return true;
    });
    return found;
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
      if (lineBoxes.isEmpty) {
        // A validated, non-collapsed range with no boxes means Flutter
        // couldn't lay it out on its own — e.g. it splits a base character
        // from a combining mark it's fused to on screen. Trusting "no boxes"
        // as "nothing to mask" would ship that glyph unmasked, so treat it
        // the same as a layout failure instead.
        printIfDebug(
          '[PostHog] textMaskPolicy range produced no boxes (it may split '
          'a grapheme cluster), masking the whole node instead.',
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
    Widget policyWidget,
    ElementGeometry geometry,
    List<Rect> rects,
  ) {
    return [
      for (final rect in rects)
        ElementData(
          type: policyWidget.runtimeType.toString(),
          rect: rect,
          widget: policyWidget,
          transform: geometry.transform,
        ),
    ];
  }
}
