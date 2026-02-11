import 'dart:io';

bool isSupportedPlatform() {
  // Allow all platforms during tests
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  return !(Platform.isLinux || Platform.isWindows);
}

bool isMacOS() {
  return Platform.isMacOS;
}
