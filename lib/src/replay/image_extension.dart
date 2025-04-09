import 'dart:ui' as ui;

extension ImageExtension on ui.Image {
  bool get isValidImageSize => width > 0 && height > 0;
}
