import 'dart:isolate';
import 'package:flutter/services.dart';

/// Gets the current isolate's debug name for IO platforms
String? getIsolateName() => Isolate.current.debugName;

/// Determines if the current isolate is the root isolate for IO platforms
/// Uses Flutter's ServicesBinding to detect the root isolate
bool isRootIsolate() {
  try {
    return ServicesBinding.rootIsolateToken != null;
  } catch (_) {
    return true;
  }
}
