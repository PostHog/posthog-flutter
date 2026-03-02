import 'package:flutter/rendering.dart';

abstract class Scaler {
  Size getScaledSize(
      double originalWidth, double originalHeight, Size targetSize, BoxFit fit);
}

class ImageScaler implements Scaler {
  double _getRatio(double originalWidth, double originalHeight) {
    return originalWidth <= 0 || originalHeight <= 0
        ? 1.0
        : originalWidth / originalHeight;
  }

  @override
  Size getScaledSize(double originalWidth, double originalHeight,
      Size targetSize, BoxFit fit) {
    final double aspectRatio = _getRatio(originalWidth, originalHeight);

    switch (fit) {
      case BoxFit.fill:
        return Size(targetSize.width, targetSize.height);
      case BoxFit.contain:
        if (targetSize.width / aspectRatio <= targetSize.height) {
          return Size(targetSize.width, targetSize.width / aspectRatio);
        }
        return Size(targetSize.height * aspectRatio, targetSize.height);
      case BoxFit.cover:
        if (targetSize.width / aspectRatio >= targetSize.height) {
          return Size(targetSize.width, targetSize.width / aspectRatio);
        }
        return Size(targetSize.height * aspectRatio, targetSize.height);
      case BoxFit.fitWidth:
        return Size(targetSize.width, targetSize.width / aspectRatio);
      case BoxFit.fitHeight:
        return Size(targetSize.height * aspectRatio, targetSize.height);
      case BoxFit.none:
        return Size(originalWidth, originalHeight);
      case BoxFit.scaleDown:
        if (originalWidth > targetSize.width ||
            originalHeight > targetSize.height) {
          return getScaledSize(
              originalWidth, originalHeight, targetSize, BoxFit.contain);
        }
        return Size(originalWidth, originalHeight);
    }
  }
}
