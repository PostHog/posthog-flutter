import 'dart:io' show Platform;

import 'android_initializer.dart';
import 'ios_initializer.dart';
import 'platform_initializer.dart';

class PlatformInitializerFactory {
  static PlatformInitializer getInitializer() {
    if (Platform.isAndroid) {
      return AndroidInitializer();
    } else if (Platform.isIOS) {
      return IOSInitializer();
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }
}
