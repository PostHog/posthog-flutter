import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Validation: Raw RGBA correctly detects image differences', () async {
    // 1. Create Base Image (Red)
    final int width = 1024;
    final int height = 1024;
    final ui.PictureRecorder recorder1 = ui.PictureRecorder();
    final ui.Canvas canvas1 = ui.Canvas(recorder1);
    final ui.Paint paint1 = ui.Paint()
      ..color = const ui.Color(0xFFFF0000); // Red
    canvas1.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint1);
    final ui.Image image1 =
        await recorder1.endRecording().toImage(width, height);

    // 2. Create Identical Image (Red)
    final ui.PictureRecorder recorder2 = ui.PictureRecorder();
    final ui.Canvas canvas2 = ui.Canvas(recorder2);
    final ui.Paint paint2 = ui.Paint()
      ..color = const ui.Color(0xFFFF0000); // Red
    canvas2.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint2);
    final ui.Image image2 =
        await recorder2.endRecording().toImage(width, height);

    // 3. Create Different Image (Blue)
    final ui.PictureRecorder recorder3 = ui.PictureRecorder();
    final ui.Canvas canvas3 = ui.Canvas(recorder3);
    final ui.Paint paint3 = ui.Paint()
      ..color = const ui.Color(0xFF0000FF); // Blue
    canvas3.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint3);
    final ui.Image image3 =
        await recorder3.endRecording().toImage(width, height);

    // 4. Get Bytes
    final bytes1 = await image1.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes2 = await image2.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes3 = await image3.toByteData(format: ui.ImageByteFormat.rawRgba);

    // 5. Assertions
    // Same images should have identical bytes
    expect(bytes1!.buffer.asUint8List(), equals(bytes2!.buffer.asUint8List()),
        reason: "Identical images should yield identical Raw RGBA bytes");

    // Different images should have different bytes
    expect(bytes1.buffer.asUint8List(),
        isNot(equals(bytes3!.buffer.asUint8List())),
        reason: "Different images should yield different Raw RGBA bytes");

    print('Validation Passed: Raw RGBA allows accurate diffing.');

    image1.dispose();
    image2.dispose();
    image3.dispose();
  });
}
