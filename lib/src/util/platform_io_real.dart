import 'dart:io';

bool isSupportedPlatform() {
  return !(Platform.isLinux || Platform.isWindows);
}
