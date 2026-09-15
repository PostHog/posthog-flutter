import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';

Future<void> expectMask(
    Rect rect, Matrix4? transform, double scale, Rect expected) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF00FF00), BlendMode.src);
  ImageMaskPainter().drawMaskedImage(
    canvas,
    [ElementData(rect: rect, type: 'test', transform: transform)],
    scale,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(12, 12);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final bytes = data.buffer.asUint8List();
    for (var y = 0; y < 12; y++) {
      for (var x = 0; x < 12; x++) {
        final i = (y * 12 + x) * 4;
        final color =
            Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
        expect(
            color,
            expected.contains(Offset(x + 0.5, y + 0.5))
                ? Colors.black
                : const Color(0xFF00FF00),
            reason: 'pixel ($x, $y)');
      }
    }
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  test('fractional mask edges round outward to opaque pixels', () async {
    await expectMask(const Rect.fromLTRB(1, 3, 2, 4), null, 0.5,
        const Rect.fromLTRB(0, 1, 1, 2));
  });

  test('transformed masks round in scaled screen space', () async {
    await expectMask(
      const Rect.fromLTRB(1, 3, 2, 4),
      Matrix4.translationValues(10, 12, 0),
      0.333,
      const Rect.fromLTRB(3, 4, 4, 6),
    );
  });

  test('bounded perspective masks retain conservative coverage', () async {
    await expectMask(
      const Rect.fromLTWH(0, 0, 10, 10),
      Matrix4.identity()..setEntry(3, 0, 0.02),
      0.5,
      const Rect.fromLTWH(0, 0, 5, 5),
    );
  });

  test('masks crossing a perspective horizon reject the frame', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    try {
      expect(
        () => ImageMaskPainter().drawMaskedImage(
          canvas,
          [
            ElementData(
              rect: const Rect.fromLTWH(0, 0, 10, 10),
              type: 'test',
              transform: Matrix4.identity()..setEntry(3, 0, -0.2),
            )
          ],
          0.5,
        ),
        throwsStateError,
      );
    } finally {
      recorder.endRecording().dispose();
    }
  });
}
