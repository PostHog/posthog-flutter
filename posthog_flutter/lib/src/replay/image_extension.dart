import 'dart:ui' as ui;

extension ImageExtension on ui.Image {
  bool get isValidSize => width > 0 && height > 0;
}
