import 'package:flutter/rendering.dart';

abstract class PositionCalculator {
  double calculateLeftPosition(AlignmentGeometry alignment, Offset offset,
      double containerWidth, double renderBoxWidth);

  double calculateTopPosition(AlignmentGeometry alignment, Offset offset,
      double containerHeight, double renderBoxHeight);
}

class DefaultPositionCalculator implements PositionCalculator {
  @override
  double calculateLeftPosition(AlignmentGeometry alignment, Offset offset,
      double containerWidth, double renderBoxWidth) {
    if (alignment == Alignment.centerLeft ||
        alignment == Alignment.bottomLeft ||
        alignment == Alignment.topLeft) {
      return offset.dx;
    } else if (alignment == Alignment.bottomRight ||
        alignment == Alignment.centerRight ||
        alignment == Alignment.topRight) {
      return offset.dx + containerWidth - renderBoxWidth;
    }

    return offset.dx + (containerWidth - renderBoxWidth) / 2;
  }

  @override
  double calculateTopPosition(AlignmentGeometry alignment, Offset offset,
      double containerHeight, double renderBoxHeight) {
    if (alignment == Alignment.topLeft ||
        alignment == Alignment.topCenter ||
        alignment == Alignment.topRight) {
      return offset.dy;
    } else if (alignment == Alignment.bottomRight ||
        alignment == Alignment.bottomLeft ||
        alignment == Alignment.bottomCenter) {
      return offset.dy + containerHeight - renderBoxHeight;
    }

    return offset.dy + (containerHeight - renderBoxHeight) / 2;
  }
}
