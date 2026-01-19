import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';
import 'package:posthog_flutter/src/replay/image_extension.dart';

import 'position_calculator.dart';
import 'scaler.dart';

class RenderImageParser extends ElementParser {
  final Scaler _scaler;
  final PositionCalculator _positionCalculator;

  RenderImageParser({
    required Scaler scaler,
    required PositionCalculator positionCalculator,
  })  : _scaler = scaler,
        _positionCalculator = positionCalculator;

  @override
  ({Rect rect, Matrix4 transform})? buildElementData(Element element) {
    final RenderImage renderImage = element.renderObject as RenderImage;
    final image = renderImage.image;
    if (!renderImage.hasSize ||
        !renderImage.size.isValidSize ||
        image == null ||
        !image.isValidSize) {
      return null;
    }

    final BoxFit fit = renderImage.fit ?? BoxFit.scaleDown;

    final Size size = _scaler.getScaledSize(
      image.width.toDouble(),
      image.height.toDouble(),
      renderImage.size,
      fit,
    );

    if (!size.isValidSize) {
      return null;
    }

    final AlignmentGeometry alignment = renderImage.alignment;

    // Calculate position within the container in local coordinates
    final double left = _positionCalculator.calculateLeftPosition(
        alignment, Offset.zero, renderImage.size.width, size.width);
    final double top = _positionCalculator.calculateTopPosition(
        alignment, Offset.zero, renderImage.size.height, size.height);

    // Store rect in local coordinates - transform handles global positioning
    final Rect localRect = Rect.fromLTWH(left, top, size.width, size.height);

    // Get the full transform from this render object to the screen
    final Matrix4 transform = renderImage.getTransformTo(null);

    return (rect: localRect, transform: transform);
  }
}
