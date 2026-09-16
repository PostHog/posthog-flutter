import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() {
  test('screenshot controls preserve native defaults', () {
    final config = PostHogSessionReplayConfig();

    expect(config.screenshotScale, 1.0);
    expect(config.screenshotCompressionQuality, 30);
    expect(config.screenshotColorMode, PostHogScreenshotColorMode.argb8888);
    expect(config.toMap(), containsPair('screenshotScale', 1.0));
    expect(config.toMap(), containsPair('screenshotCompressionQuality', 30));
    expect(config.toMap(), containsPair('screenshotColorMode', 'argb8888'));
  });

  test('screenshot controls are included in the setup configuration', () {
    final config = PostHogConfig('test_project_token')
      ..sessionReplayConfig.screenshotScale = 0.333
      ..sessionReplayConfig.screenshotCompressionQuality = 75
      ..sessionReplayConfig.screenshotColorMode =
          PostHogScreenshotColorMode.rgb565;

    final replay = config.toMap()['sessionReplayConfig'] as Map;
    expect(replay['screenshotScale'], 0.333);
    expect(replay['screenshotCompressionQuality'], 75);
    expect(replay['screenshotColorMode'], 'rgb565');
  });

  test('screenshot scale clamps finite values and normalizes non-finite values',
      () {
    final config = PostHogSessionReplayConfig();
    for (final entry in <(double, double)>[
      (-1, 0.1),
      (0, 0.1),
      (0.1, 0.1),
      (0.333, 0.333),
      (0.5, 0.5),
      (1, 1),
      (2, 1),
      (double.nan, 1),
      (double.infinity, 1),
      (double.negativeInfinity, 1),
    ]) {
      config.screenshotScale = entry.$1;
      expect(config.screenshotScale, entry.$2);
      expect(config.toMap()['screenshotScale'], entry.$2);
    }
  });

  test('screenshot compression quality clamps to the encoder range', () {
    final config = PostHogSessionReplayConfig();
    for (final entry in <(int, int)>[
      (-1, 0),
      (0, 0),
      (30, 30),
      (75, 75),
      (100, 100),
      (101, 100),
    ]) {
      config.screenshotCompressionQuality = entry.$1;
      expect(config.screenshotCompressionQuality, entry.$2);
      expect(config.toMap()['screenshotCompressionQuality'], entry.$2);
    }
  });
}
