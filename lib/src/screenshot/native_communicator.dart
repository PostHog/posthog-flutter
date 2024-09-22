import 'package:flutter/services.dart';

class NativeCommunicator {
  static const MethodChannel _channel = MethodChannel('posthog_flutter');

  Future<void> sendImageToNative(Uint8List imageBytes) async {
    try {
      await _channel
          .invokeMethod('sendReplayScreenshot', {'imageBytes': imageBytes});
    } catch (e) {
      print('Error sending image to native: $e');
    }
  }
}
