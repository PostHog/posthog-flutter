import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

import 'posthog_flutter_platform_interface_fake.dart';

const _fourLines = 'line one\nline two\nline three\nline four';
const _black = Color(0xFF000000);

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
}

void main() {
  setUp(() async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    final config = PostHogConfig('test_project_token');
    config.sessionReplayConfig.maskAllTexts = true;
    await Posthog().setup(config);
    // the controller singleton may have been created before this setup
    PostHogMaskController.instance.refreshParsers(config.sessionReplayConfig);
  });

  tearDown(() async {
    PostHogMaskController.instance.refreshParsers(null);
    await Posthog().close();
  });

  Future<void> pumpField(WidgetTester tester, Widget field) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: PostHogMaskController.instance.containerKey,
          child: Scaffold(
            body: Center(child: SizedBox(width: 300, child: field)),
          ),
        ),
      ),
    );
  }

  TextEditingController controller(String text) {
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    return controller;
  }

  RenderObject container() =>
      PostHogMaskController.instance.containerKey.currentContext!
          .findRenderObject()!;

  RenderEditable editable(WidgetTester tester) =>
      tester.allRenderObjects.whereType<RenderEditable>().single;

  /// The field's laid-out bounds in the screenshot container's coordinates.
  Rect editableBounds(WidgetTester tester) {
    final renderObject = editable(tester);
    return MatrixUtils.transformRect(
      renderObject.getTransformTo(container()),
      Offset.zero & renderObject.size,
    );
  }

  /// The `_Editable` mask in the screenshot container's coordinates.
  Rect editableMask() {
    final elements = PostHogMaskController.instance
        .getMaskElements(includeAllWidgets: true)!;
    final element = elements.singleWhere((e) => e.type == '_Editable');
    return MatrixUtils.transformRect(element.transform!, element.rect);
  }

  testWidgets('TextField(maxLines: null) is masked over its full height',
      (tester) async {
    await pumpField(
      tester,
      TextField(maxLines: null, controller: controller(_fourLines)),
    );

    final renderObject = editable(tester);
    expect(renderObject.maxLines, isNull);
    expect(
      renderObject.size.height,
      moreOrLessEquals(4 * renderObject.preferredLineHeight, epsilon: 1),
    );

    final mask = editableMask();
    expect(mask.height, moreOrLessEquals(renderObject.size.height));
    expect(mask, rectMoreOrLessEquals(editableBounds(tester)));
  });

  testWidgets('TextField(expands: true) is masked over the box it fills',
      (tester) async {
    await pumpField(
      tester,
      SizedBox(
        height: 200,
        width: 300,
        child: TextField(
          maxLines: null,
          expands: true,
          decoration: null,
          controller: controller('one line'),
        ),
      ),
    );

    final renderObject = editable(tester);
    expect(renderObject.size.height, greaterThanOrEqualTo(200));

    final mask = editableMask();
    expect(mask.height, greaterThanOrEqualTo(200));
    expect(mask, rectMoreOrLessEquals(editableBounds(tester)));
  });

  for (final (name, build)
      in <(String, Widget Function(TextEditingController))>[
    ('TextFormField', (c) => TextFormField(maxLines: null, controller: c)),
    (
      'CupertinoTextField',
      (c) => CupertinoTextField(maxLines: null, controller: c)
    ),
  ]) {
    testWidgets('$name(maxLines: null) is masked over its full height',
        (tester) async {
      await pumpField(tester, build(controller(_fourLines)));

      final renderObject = editable(tester);
      expect(
        renderObject.size.height,
        moreOrLessEquals(4 * renderObject.preferredLineHeight, epsilon: 1),
      );
      expect(
        editableMask().height,
        moreOrLessEquals(renderObject.size.height),
      );
    });
  }

  testWidgets('TextField(maxLines: 3) still masks three lines', (tester) async {
    await pumpField(
      tester,
      TextField(maxLines: 3, controller: controller(_fourLines)),
    );

    final renderObject = editable(tester);
    expect(
      editableMask().height,
      moreOrLessEquals(3 * renderObject.preferredLineHeight),
    );
  });

  testWidgets('a dense single-line field still masks at least one line',
      (tester) async {
    await pumpField(
      tester,
      TextField(
        decoration: const InputDecoration(isDense: true),
        controller: controller('one line'),
      ),
    );

    final renderObject = editable(tester);
    expect(
      editableMask().height,
      greaterThanOrEqualTo(renderObject.preferredLineHeight),
    );
  });

  testWidgets('a field laid out shorter than its text still masks one line',
      (tester) async {
    await pumpField(
      tester,
      SizedBox(
        height: 4,
        width: 300,
        child: TextField(decoration: null, controller: controller('one line')),
      ),
    );

    final renderObject = editable(tester);
    expect(
        renderObject.size.height, lessThan(renderObject.preferredLineHeight));
    expect(
      editableMask().height,
      moreOrLessEquals(renderObject.preferredLineHeight),
    );
  });

  testWidgets('the masked capture blacks out the fourth line of the field',
      (tester) async {
    const textColor = Color(0xFF1A237E);
    await pumpField(
      tester,
      TextField(
        maxLines: null,
        decoration: null,
        style: const TextStyle(fontSize: 24, height: 1, color: textColor),
        controller: controller('XXXX\nXXXX\nXXXX\nXXXX'),
      ),
    );

    final renderObject = editable(tester);
    final bounds = editableBounds(tester);
    // the middle of the first glyph on line four
    final x = (bounds.left + 12).round();
    final y = (bounds.top + 3.5 * renderObject.preferredLineHeight).round();

    // The same three stages as ScreenshotCapturer: snapshot the container,
    // walk the tree for mask rects, paint the masks over the snapshot.
    final boundary = container() as RenderRepaintBoundary;
    final elements = PostHogMaskController.instance
        .getMaskElements(includeAllWidgets: true)!;
    // real async work: it never completes inside the test's FakeAsync zone
    final (unmasked, masked) = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());
      ImageMaskPainter().drawMaskedImage(canvas, elements, 1);
      final maskedImage =
          await recorder.endRecording().toImage(image.width, image.height);
      final colors =
          (await _pixel(image, x, y), await _pixel(maskedImage, x, y));
      image.dispose();
      maskedImage.dispose();
      return colors;
    }))!;

    expect(unmasked, textColor);
    expect(masked, _black);
  });
}
