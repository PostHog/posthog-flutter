import 'package:posthog_flutter/src/posthog_config.dart';

extension SessionReplayMasking on PostHogSessionReplayConfig {
  bool get masksAnyContent =>
      maskAllTexts ||
      maskAllImages ||
      maskCustomPaint ||
      textMaskPolicy != null;
}
