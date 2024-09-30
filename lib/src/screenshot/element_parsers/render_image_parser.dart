import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:posthog_flutter/src/screenshot/element_parsers/element_parser.dart';

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
  Rect? buildElementRect(Element element, Rect? parentRect) {
    final RenderImage renderImage = element.renderObject as RenderImage;
    if (!renderImage.hasSize) {
      return null;
    }

    final offset = renderImage.localToGlobal(Offset.zero);
    final BoxFit fit = renderImage.fit ?? BoxFit.scaleDown;

    final Size size = _scaler.getScaledSize(
      renderImage.image!.width.toDouble(),
      renderImage.image!.height.toDouble(),
      renderImage.size,
      fit,
    );

    final AlignmentGeometry alignment = renderImage.alignment;

    final double left =
        _positionCalculator.calculateLeftPosition(alignment, offset, renderImage.size.width, size.width);
    final double top =
        _positionCalculator.calculateTopPosition(alignment, offset, renderImage.size.height, size.height);

    return Rect.fromLTWH(left, top, size.width, size.height);
  }
}
