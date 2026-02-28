import 'dart:io';

bool isSupportedPlatform() {
  // Allow all platforms during tests
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return true;
  }
  // All platforms are now supported:
  // iOS, Android, macOS use native method channels
  // Web uses JS interop
  // Linux and Windows use posthog_dart SDK
  return true;
}

bool isMacOS() {
  return Platform.isMacOS;
}
