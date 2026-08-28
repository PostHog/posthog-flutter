import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

const _topLeft = Color(0xFFFF0000);
const _topRight = Color(0xFF0000FF);
const _bottomLeft = Color(0xFFFFFF00);
const _bottomRight = Color(0xFFFF00FF);
const _background = Color(0xFF00FF00);

/// A stand-in for the native crop: an axis-aligned screen capture of the view,
/// [w] x [h], with each quadrant a different colour so a rotation or a flip of
/// the result is detectable.
Future<ui.Image> _screenCrop(int w, int h) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final halfW = w / 2;
  final halfH = h / 2;
  canvas.drawRect(Rect.fromLTWH(0, 0, halfW, halfH), Paint()..color = _topLeft);
  canvas.drawRect(
      Rect.fromLTWH(halfW, 0, halfW, halfH), Paint()..color = _topRight);
  canvas.drawRect(
      Rect.fromLTWH(0, halfH, halfW, halfH), Paint()..color = _bottomLeft);
  canvas.drawRect(
      Rect.fromLTWH(halfW, halfH, halfW, halfH), Paint()..color = _bottomRight);
  return recorder.endRecording().toImage(w, h);
}

Future<ui.Image> _composite(
  ui.Image crop,
  Matrix4 transform,
  Rect viewRect,
  Rect visibleRect,
) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 200), Paint()..color = _background);
  compositeRevealedImage(canvas, crop, transform, viewRect, visibleRect);
  return recorder.endRecording().toImage(100, 200);
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
}

/// The composited screen must reproduce the crop quadrant for quadrant.
Future<void> _expectCropReproduced(ui.Image image) async {
  expect(await _pixel(image, 25, 50), _topLeft);
  expect(await _pixel(image, 75, 50), _topRight);
  expect(await _pixel(image, 25, 150), _bottomLeft);
  expect(await _pixel(image, 75, 150), _bottomRight);
}

void main() {
  // A quarter turn about the origin, shifted back so the view's 200x100 local
  // rect lands on the 100x200 screen footprint the crop was taken from.
  final quarterTurn = Matrix4.identity()
    ..translateByDouble(100.0, 0.0, 0.0, 1.0)
    ..rotateZ(pi / 2);
  final mirrored = Matrix4.identity()
    ..translateByDouble(100.0, 0.0, 0.0, 1.0)
    ..multiply(Matrix4.diagonal3Values(-1, 1, 1));

  test('an unrotated view lands where the crop was taken', () async {
    final image = await _composite(
      await _screenCrop(100, 200),
      Matrix4.identity(),
      const Rect.fromLTWH(0, 0, 100, 200),
      const Rect.fromLTWH(0, 0, 100, 200),
    );
    await _expectCropReproduced(image);
  });

  test('a quarter-turned view is not turned a second time', () async {
    final image = await _composite(
      await _screenCrop(100, 200),
      quarterTurn,
      const Rect.fromLTWH(0, 0, 200, 100),
      const Rect.fromLTWH(0, 0, 200, 100),
    );
    await _expectCropReproduced(image);
  });

  test('a mirrored view is not mirrored a second time', () async {
    final image = await _composite(
      await _screenCrop(100, 200),
      mirrored,
      const Rect.fromLTWH(0, 0, 100, 200),
      const Rect.fromLTWH(0, 0, 100, 200),
    );
    await _expectCropReproduced(image);
  });

  test('only the visible part of a clipped view is painted', () async {
    final image = await _composite(
      await _screenCrop(100, 200),
      Matrix4.identity(),
      const Rect.fromLTWH(0, 0, 100, 200),
      const Rect.fromLTWH(0, 0, 100, 100),
    );
    expect(await _pixel(image, 25, 50), _topLeft);
    expect(await _pixel(image, 75, 50), _topRight);
    expect(await _pixel(image, 25, 150), _background);
    expect(await _pixel(image, 75, 150), _background);
  });

  test('a clipped quarter-turned view is clipped in its own space', () async {
    final image = await _composite(
      await _screenCrop(100, 200),
      quarterTurn,
      const Rect.fromLTWH(0, 0, 200, 100),
      const Rect.fromLTWH(0, 0, 60, 100),
    );
    // The turn sends the visible 60 of the view's 200 wide span to the top
    // 60 px of the screen footprint, leaving the crop's own colours in place.
    expect(await _pixel(image, 25, 20), _topLeft);
    expect(await _pixel(image, 75, 20), _topRight);
    expect(await _pixel(image, 25, 150), _background);
    expect(await _pixel(image, 75, 150), _background);
  });

  test('an eighth turn does not paint the corners of the clip hull', () async {
    // A quarter turn maps an axis-aligned rect onto another axis-aligned rect,
    // so it cannot tell the view-space clip apart from that rect's device-space
    // hull. At 45 degrees the hull is twice the area of the real clip.
    final eighthTurn = Matrix4.identity()
      ..translateByDouble(50.0, 20.0, 0.0, 1.0)
      ..rotateZ(pi / 4);
    final image = await _composite(
      await _screenCrop(100, 200),
      eighthTurn,
      const Rect.fromLTWH(0, 0, 60, 60),
      const Rect.fromLTWH(0, 0, 60, 60),
    );
    expect(await _pixel(image, 40, 60), _topLeft);
    expect(await _pixel(image, 15, 30), _background);
    expect(await _pixel(image, 85, 30), _background);
    expect(await _pixel(image, 15, 95), _background);
    expect(await _pixel(image, 85, 95), _background);
  });

  test('a singular transform paints nothing rather than throwing', () async {
    final image = await _composite(
      await _screenCrop(100, 200),
      Matrix4.diagonal3Values(0, 1, 1),
      const Rect.fromLTWH(0, 0, 100, 200),
      const Rect.fromLTWH(0, 0, 100, 200),
    );
    expect(await _pixel(image, 50, 100), _background);
  });

  test('a failed native capture masks only the visible region', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 200), Paint()..color = _background);
    await ScreenshotCapturer(PostHogConfig('test')).debugMaskFailedCapture(
      canvas,
      const Rect.fromLTWH(0, 0, 100, 200),
      const Rect.fromLTWH(0, 0, 100, 100),
      Matrix4.identity(),
    );
    final image = await recorder.endRecording().toImage(100, 200);
    expect(await _pixel(image, 50, 50), const Color(0xFF000000));
    expect(await _pixel(image, 50, 150), _background);
  });
}
