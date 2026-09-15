import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/mask/unmask_rects.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

class UnmaskElementParser extends ElementParser {
  @override
  ElementGeometry? buildElementData(Element element) {
    final geometry = super.buildElementData(element);
    if (geometry == null) return null;
    final renderObject = element.renderObject;
    final container = PostHogMaskController.instance.containerKey.currentContext
        ?.findRenderObject();
    var rect = geometry.rect;
    RenderObject? child;
    renderObject?.visitChildren((candidate) => child ??= candidate);
    var node = renderObject;
    while (node != null) {
      if ((node is RenderOpacity &&
              Color.getAlphaFromOpacity(node.opacity) == 0) ||
          (node is RenderAnimatedOpacity &&
              Color.getAlphaFromOpacity(node.opacity.value) == 0) ||
          (node is RenderSliverOpacity &&
              Color.getAlphaFromOpacity(node.opacity) == 0) ||
          (node is RenderSliverAnimatedOpacity &&
              Color.getAlphaFromOpacity(node.opacity.value) == 0)) {
        return (rect: Rect.zero, transform: geometry.transform);
      }
      final clip =
          child == null ? null : node.describeApproximatePaintClip(child!);
      if (clip != null) {
        // A bounding box of a curved/custom clip can expose pixels that were
        // never part of the visible unmask region. Only use rectangular clips.
        if (node is! RenderClipRect && node is! RenderViewportBase) {
          return (rect: Rect.zero, transform: geometry.transform);
        }
        final inverse = Matrix4.tryInvert(renderObject!.getTransformTo(node));
        final localClip =
            inverse == null ? null : axisAlignedUnmaskRect(clip, inverse);
        if (localClip == null) {
          return (rect: Rect.zero, transform: geometry.transform);
        }
        rect = rect.intersect(localClip);
      }
      if (identical(node, container)) break;
      child = node;
      node = node.parent;
    }
    return (rect: rect, transform: geometry.transform);
  }
}
