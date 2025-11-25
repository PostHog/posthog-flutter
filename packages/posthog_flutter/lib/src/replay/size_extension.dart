import 'package:flutter/material.dart';

extension SizeExtension on Size {
  bool get isValidSize => width > 0 && height > 0;
}
