import 'package:flutter/services.dart';

/*
    * TEMPORARY CLASS FOR TESTING PURPOSES
    * This function sends a screenshot to PostHog.
    * It should be removed or refactored in the other version.
    */
class NativeCommunicator {
  static const MethodChannel _channel = MethodChannel('posthog_flutter');

  Future<void> sendImageAndRectsToNative(Uint8List imageBytes, List<Map<String, double>> rectsData) async {
    try {
      await _channel.invokeMethod('sendReplayScreenshot', {
        'imageBytes': imageBytes,
        'rects': rectsData, // Enviando os dados dos rects também
      });
    } catch (e) {
      print('Error sending image and rects to native: $e');
    }
  }
}
