import 'package:flutter/services.dart';

/*
    * TEMPORARY CLASS FOR TESTING PURPOSES
    * This function sends a screenshot to PostHog.
    * It should be removed or refactored in the other version.
    */
class NativeCommunicator {
  static const MethodChannel _channel = MethodChannel('posthog_flutter');

  Future<void> sendFullSnapshot(Uint8List imageBytes, {required int id}) async {
    try {
      await _channel.invokeMethod('sendFullSnapshot', {
        'imageBytes': imageBytes,
        'id': id,
      });
    } catch (e) {
      print('Error sending full snapshot to native: $e');
    }
  }

  Future<void> sendIncrementalSnapshot(Uint8List imageBytes,
      {required int id}) async {
    try {
      await _channel.invokeMethod('sendIncrementalSnapshot', {
        'imageBytes': imageBytes,
        'id': id,
      });
    } catch (e) {
      print('Error sending incremental snapshot to native: $e');
    }
  }
}
