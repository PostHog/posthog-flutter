import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart'
    as replay;

import 'posthog_flutter_platform_interface_fake.dart';
import 'replay_capture_settle.dart';

class _ValuePainter extends CustomPainter {
  const _ValuePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: const TextSpan(
        text: '₦2,450,000.00',
        style: TextStyle(fontSize: 12, color: Colors.black),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset.zero);
    text.dispose();
  }

  @override
  bool shouldRepaint(covariant _ValuePainter oldDelegate) => false;
}

void main() {
  const paintKey = ValueKey('sensitive-paint');
  final controller = PostHogMaskController.instance;

  setUp(() {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
  });

  Future<void> setup({
    bool texts = true,
    bool images = true,
    bool? customPaint,
  }) async {
    final config = PostHogConfig('test_project_token');
    config.sessionReplayConfig
      ..maskAllTexts = texts
      ..maskAllImages = images;
    if (customPaint != null) {
      config.sessionReplayConfig.maskCustomPaint = customPaint;
    }
    await Posthog().setup(config);
    controller.refreshParsers(config.sessionReplayConfig);
  }

  tearDown(() async {
    controller.refreshParsers(null);
    await Posthog().close();
  });

  Widget painted({bool foreground = false}) => CustomPaint(
        key: paintKey,
        size: const Size(200, 40),
        painter: foreground ? null : const _ValuePainter(),
        foregroundPainter: foreground ? const _ValuePainter() : null,
      );

  Future<void> pumpTree(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: controller.containerKey,
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [const Text('₦2,450,000.00'), child],
            ),
          ),
        ),
      ),
    );
  }

  List<Rect> maskRects({bool includeAllWidgets = true}) {
    final elements = controller.getMaskElements(
      includeAllWidgets: includeAllWidgets,
    );
    expect(elements, isNotNull);
    return elements!
        .map((element) => element.transform == null
            ? element.rect
            : MatrixUtils.transformRect(element.transform!, element.rect))
        .toList();
  }

  Rect boundsOf(WidgetTester tester, Finder finder) {
    final renderObject = tester.renderObject<RenderBox>(finder);
    return MatrixUtils.transformRect(
      renderObject.getTransformTo(
        controller.containerKey.currentContext!.findRenderObject(),
      ),
      renderObject.paintBounds,
    );
  }

  test('custom-paint masking is disabled by default', () {
    expect(PostHogSessionReplayConfig().maskCustomPaint, isFalse);
    controller.refreshParsers(null);
    expect(controller.parsers, isNot(contains('RenderCustomPaint')));
  });

  testWidgets('leaves CustomPaint visible by default', (tester) async {
    await setup();
    await pumpTree(tester, painted());

    expect(
        maskRects(), isNot(contains(boundsOf(tester, find.byKey(paintKey)))));
    expect(maskRects(), contains(boundsOf(tester, find.byType(Text))));
  });

  for (final foreground in [false, true]) {
    for (final customPaint in [false, true]) {
      for (final texts in [false, true]) {
        for (final images in [false, true]) {
          testWidgets(
              'CustomPaint foreground=$foreground customPaint=$customPaint '
              'texts=$texts images=$images', (tester) async {
            await setup(texts: texts, images: images, customPaint: customPaint);
            await pumpTree(tester, painted(foreground: foreground));

            final rects = maskRects(
              includeAllWidgets: texts || images || customPaint,
            );
            final paintRect = boundsOf(tester, find.byKey(paintKey));
            expect(rects.contains(paintRect), customPaint);
            expect(
              rects.contains(boundsOf(tester, find.byType(Text))),
              texts,
            );
          });
        }
      }
    }
  }

  testWidgets('explicit mask still covers CustomPaint with both flags off',
      (tester) async {
    await setup(texts: false, images: false);
    await pumpTree(tester, PostHogMaskWidget(child: painted()));

    expect(
      maskRects(includeAllWidgets: false),
      contains(boundsOf(tester, find.byKey(paintKey))),
    );
  });

  testWidgets('does not mask an empty CustomPaint but still walks its child',
      (tester) async {
    await setup(customPaint: true);
    await pumpTree(
      tester,
      const CustomPaint(
        key: paintKey,
        child: SizedBox(
          width: 200,
          height: 100,
          child: Align(child: Text('child text')),
        ),
      ),
    );

    final rects = maskRects();
    expect(rects, isNot(contains(boundsOf(tester, find.byKey(paintKey)))));
    expect(rects, contains(boundsOf(tester, find.text('child text'))));
  });

  testWidgets('masks children underneath a foreground painter', (tester) async {
    await setup(customPaint: true);
    await pumpTree(
      tester,
      const CustomPaint(
        key: paintKey,
        foregroundPainter: _ValuePainter(),
        child: SizedBox(width: 200, height: 100),
      ),
    );

    expect(maskRects(), contains(boundsOf(tester, find.byKey(paintKey))));
  });

  testWidgets('conservatively masks a full-window debug banner when opted in',
      (tester) async {
    await setup(customPaint: true);
    await tester.pumpWidget(
      RepaintBoundary(
        key: controller.containerKey,
        child: const MaterialApp(home: Scaffold(body: Text('secret'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      maskRects(),
      contains(boundsOf(tester, find.byKey(controller.containerKey))),
    );
  });

  testWidgets('uses painted bounds and transform for CustomPaint masks',
      (tester) async {
    await setup(customPaint: true);
    await pumpTree(
      tester,
      Transform.translate(
        offset: const Offset(30, 20),
        child: Transform.scale(
          scale: 1.5,
          alignment: Alignment.topLeft,
          child: painted(),
        ),
      ),
    );

    final paintRect = boundsOf(tester, find.byKey(paintKey));
    expect(paintRect.size, const Size(300, 60));
    expect(maskRects(), contains(paintRect));
  });

  testWidgets('native captureScreenshot honors custom-paint masking on its own',
      (tester) async {
    await setup(texts: false, images: false, customPaint: true);
    await pumpTree(tester, painted());

    const channel = MethodChannel('posthog_flutter');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSessionReplayState') {
        return {'isActive': true, 'sessionId': 'custom-paint-session'};
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final capturer = replay.ScreenshotCapturer(Posthog().config!);
    addTearDown(capturer.cancel);
    var completed = false;
    final capture = capturer.captureScreenshot().whenComplete(() {
      completed = true;
    });
    await settleUntil(tester, () => completed);
    expect(completed, isTrue);
    final captured = await capture;
    expect(captured, isNotNull);

    final paintRect = boundsOf(tester, find.byKey(paintKey));
    final boundary = tester.renderObject<RenderBox>(
      find.byKey(controller.containerKey),
    );
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(captured!.imageBytes);
      final image = (await codec.getNextFrame()).image;
      try {
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final ratio = image.width / boundary.size.width;
        final x = (5 * ratio).floor();
        final insideY = ((paintRect.bottom - 5) * ratio).floor();
        final outsideY = ((paintRect.bottom + 10) * ratio).floor();
        expect(data.getUint32((insideY * image.width + x) * 4), 0x000000ff);
        expect(data.getUint32((outsideY * image.width + x) * 4), 0xffffffff);
      } finally {
        image.dispose();
        codec.dispose();
      }
    });
  }, skip: kIsWeb);

  testWidgets('masking replaces custom-painted screenshot pixels with black',
      (tester) async {
    await setup(texts: false, images: false, customPaint: true);
    await pumpTree(tester, painted());

    final boundary = controller.containerKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final elements = controller.getMaskElements(includeAllWidgets: true)!;
    final paintRect = boundsOf(tester, find.byKey(paintKey));

    await tester.runAsync(() async {
      final screenshot = await boundary.toImage(pixelRatio: 2);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawImage(screenshot, Offset.zero, Paint());
      ImageMaskPainter().drawMaskedImage(canvas, elements, 2);
      final picture = recorder.endRecording();
      final masked = await picture.toImage(screenshot.width, screenshot.height);
      try {
        final before = (await screenshot.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final after = (await masked.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var originalBlackPixels = 0;
        var originalWhitePixels = 0;
        var maskedBlackPixels = 0;
        var totalPixels = 0;
        for (var y = (paintRect.top * 2).ceil();
            y < (paintRect.bottom * 2).floor();
            y++) {
          for (var x = (paintRect.left * 2).ceil();
              x < (paintRect.right * 2).floor();
              x++) {
            final offset = (y * screenshot.width + x) * 4;
            if (before.getUint32(offset) == 0x000000ff) originalBlackPixels++;
            if (before.getUint32(offset) == 0xffffffff) originalWhitePixels++;
            if (after.getUint32(offset) == 0x000000ff) maskedBlackPixels++;
            totalPixels++;
          }
        }
        expect(originalBlackPixels, greaterThan(0));
        expect(originalWhitePixels, greaterThan(0));
        expect(maskedBlackPixels, totalPixels);
        final outside = ((screenshot.height - 10) * screenshot.width +
                screenshot.width -
                10) *
            4;
        expect(before.getUint32(outside), 0xffffffff);
        expect(after.getUint32(outside), 0xffffffff);
      } finally {
        screenshot.dispose();
        masked.dispose();
        picture.dispose();
      }
    });
  });
}
