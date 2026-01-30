import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/vendor/equality.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Benchmark: Compare PNG vs Raw RGBA encoding speed', () async {
    // Create a 1024x1024 image to simulate a screenshot
    final int width = 1024;
    final int height = 1024;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    // Draw something complex to avoid compression triviality? No, a red square is fine.
    final ui.Paint paint = ui.Paint()..color = const ui.Color(0xFFFF0000);
    canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint);
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(width, height);

    print('\n--- Benchmark Results (${width}x$height Image) ---');

    // 1. Measure PNG Encoding + Compare (Old Method)
    final stopwatchPng = Stopwatch()..start();
    // In the old way, we would capture PNG, then possibly compare.
    // Assuming the comparison would be on the bytes.
    final pngBytes1 = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    // Simulate a second capture
    final pngBytes2 = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();

    // Compare
    bool isPngEqual = const PHListEquality().equals(pngBytes1, pngBytes2);
    stopwatchPng.stop();
    print(
        'PNG Encoding (x2) + Compare: ${stopwatchPng.elapsedMicroseconds}µs (Equal: $isPngEqual)');

    // 2. Measure Raw RGBA Encoding + Compare (New Method)
    final stopwatchRaw = Stopwatch()..start();
    final rawBytes1 =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
    final rawBytes2 =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();

    // Compare
    bool isRawEqual = const PHListEquality().equals(rawBytes1, rawBytes2);
    stopwatchRaw.stop();
    print(
        'Raw RGBA Encoding (x2) + Compare: ${stopwatchRaw.elapsedMicroseconds}µs (Equal: $isRawEqual)');

    final pngMicros = stopwatchPng.elapsedMicroseconds;
    final rawMicros = stopwatchRaw.elapsedMicroseconds;

    // Avoid division by zero
    final safeRawMicros = rawMicros == 0 ? 1 : rawMicros;

    final improvement = pngMicros / safeRawMicros;
    print(
        'Speedup Factor (End-to-End): ${improvement.toStringAsFixed(1)}x faster');
    print('--------------------------------------------------\n');

    image.dispose();
  });
}
