import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

import 'posthog_flutter_platform_interface_fake.dart';

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

  Future<void> setup({bool texts = true, bool images = true}) async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    final config = PostHogConfig('test_project_token');
    config.sessionReplayConfig
      ..maskAllTexts = texts
      ..maskAllImages = images;
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

  for (final foreground in [false, true]) {
    for (final texts in [false, true]) {
      for (final images in [false, true]) {
        testWidgets(
            'masks CustomPaint foreground=$foreground texts=$texts images=$images',
            (tester) async {
          await setup(texts: texts, images: images);
          await pumpTree(tester, painted(foreground: foreground));

          final rects = maskRects(includeAllWidgets: texts || images);
          final paintRect = boundsOf(tester, find.byKey(paintKey));
          expect(rects.contains(paintRect), texts || images);
          expect(
            rects.contains(boundsOf(tester, find.byType(Text))),
            texts,
          );
        });
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
    await setup();
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
    await setup();
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

  testWidgets('conservatively masks a full-window debug banner',
      (tester) async {
    await setup();
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
    await setup();
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

  testWidgets('masking replaces custom-painted screenshot pixels with black',
      (tester) async {
    await setup();
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
