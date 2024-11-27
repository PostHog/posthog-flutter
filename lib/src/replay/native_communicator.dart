import 'package:flutter/services.dart';
import 'package:posthog_flutter/src/util/logging.dart';

/*
    * TEMPORARY CLASS FOR TESTING PURPOSES
    * This function sends a screenshot to PostHog.
    * It should be removed or refactored in the other version.
    */
class NativeCommunicator {
  static const MethodChannel _channel = MethodChannel('posthog_flutter');

  Future<void> sendFullSnapshot(Uint8List imageBytes,
      {required int id, required int x, required int y}) async {
    try {
      await _channel.invokeMethod('sendFullSnapshot', {
        'imageBytes': imageBytes,
        'id': id,
        'x': x,
        'y': y,
      });
    } catch (e) {
      printIfDebug('Error sending full snapshot to native: $e');
    }
  }

  Future<void> sendMetaEvent(
      {required int width,
      required int height,
      required String? screen}) async {
    try {
      await _channel.invokeMethod('sendMetaEvent', {
        'width': width,
        'height': height,
        'screen': screen,
      });
    } catch (e) {
      printIfDebug('Error sending full snapshot to native: $e');
    }
  }

  Future<bool> isSessionReplayActive() async {
    try {
      return await _channel.invokeMethod('isSessionReplayActive');
    } catch (e) {
      printIfDebug('Error sending full snapshot to native: $e');
      return false;
    }
  }
}
