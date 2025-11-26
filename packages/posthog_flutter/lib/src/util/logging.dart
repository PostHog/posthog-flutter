import 'package:flutter/foundation.dart';

void printIfDebug(String message) {
  if (kDebugMode) {
    print(message);
  }
}
