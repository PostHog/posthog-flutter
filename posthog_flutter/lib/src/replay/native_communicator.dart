import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:posthog_flutter/src/util/logging.dart';

class NativeCommunicator {
  static const MethodChannel _channel = MethodChannel('posthog_flutter');

  Future<void> sendFullSnapshot(
    Uint8List imageBytes, {
    required int id,
    required int x,
    required int y,
  }) async {
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

  Future<void> sendMetaEvent({
    required int width,
    required int height,
    required String? screen,
  }) async {
    try {
      await _channel.invokeMethod('sendMetaEvent', {
        'width': width,
        'height': height,
        'screen': screen,
      });
    } catch (e) {
      printIfDebug('Error sending meta event to native: $e');
    }
  }

  Future<bool> isSessionReplayActive() async {
    if (kIsWeb) {
      // Flutter doesn't capture screenshots on web, JS SDK handles session replay
      return false;
    }
    try {
      return await _channel.invokeMethod('isSessionReplayActive');
    } catch (e) {
      printIfDebug('Error checking session replay status: $e');
      return false;
    }
  }

  Future<List<Uint8List?>> captureNativeScreenshots(
      List<Map<String, int>> views) async {
    if (kIsWeb || views.isEmpty) {
      return List.filled(views.length, null);
    }
    try {
      final raw = await _channel.invokeListMethod<Object?>(
        'captureNativeScreenshots',
        {'views': views},
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      if (raw == null) return List.filled(views.length, null);
      return raw.map((e) => e as Uint8List?).toList();
    } catch (e) {
      printIfDebug('Error capturing native screenshots: $e');
      return List.filled(views.length, null);
    }
  }

  /// Asks the native occlusion detector to bridge-capture native screens for
  /// the current occlusion episode; the native side disables bridging itself
  /// when the episode ends. [episode] lets the native side decline a stale
  /// request that arrives after its episode ended — accepting one would re-arm
  /// the bridge for an episode Dart never asked about. Returns false when the
  /// native side declined, so the caller can fall back to a placeholder.
  Future<bool> enableNativeBridge({required int episode}) async {
    if (kIsWeb) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'enableNativeBridge',
            {'episode': episode},
          ) ??
          false;
    } catch (e) {
      printIfDebug('Error enabling native bridge: $e');
      return false;
    }
  }
}
