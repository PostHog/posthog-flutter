import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/session_replay_config_extension.dart';

void main() {
  for (var flags = 0; flags < 8; flags++) {
    test('masksAnyContent reflects masking flags $flags', () {
      final config = PostHogSessionReplayConfig()
        ..maskAllTexts = flags & 1 != 0
        ..maskAllImages = flags & 2 != 0
        ..maskCustomPaint = flags & 4 != 0;
      expect(config.masksAnyContent, flags != 0);
      config
        ..maskAllTexts = false
        ..maskAllImages = false
        ..maskCustomPaint = false;
      expect(config.masksAnyContent, isFalse);
    });
  }
}
