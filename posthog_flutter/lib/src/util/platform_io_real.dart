import 'dart:io';

bool isSupportedPlatform() {
  // Allow all platforms during tests
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  return !(Platform.isLinux || Platform.isWindows);
}

bool isMacOS() {
  // Tests run on a macOS host but target the mocked iOS/Android channel
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return false;
  }
  return Platform.isMacOS;
}
