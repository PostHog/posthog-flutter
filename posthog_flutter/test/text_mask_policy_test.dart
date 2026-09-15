import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/session_replay_config_extension.dart';

import 'posthog_flutter_platform_interface_fake.dart';

const _textColor = Color(0xFF1A237E);
const _black = Color(0xFF000000);

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
}

List<String> _substrings(String text, PostHogTextMask mask) {
  final ranges = switch (mask) {
    PostHogTextMaskOnly(:final ranges) => ranges,
    PostHogTextMaskExcept(:final ranges) => ranges,
    _ => throw StateError('expected a ranged decision, got $mask'),
  };
  return [for (final r in ranges) text.substring(r.start, r.end)];
}

void main() {
  group('PostHogTextMaskPolicies', () {
    test('digits masks a formatted amount as one run', () {
      const text = 'Balance ₦2,450,000.00 available';
      final mask = PostHogTextMaskPolicies.digits()(text);
      expect(mask, isA<PostHogTextMaskOnly>());
      expect(_substrings(text, mask), ['2,450,000.00']);
    });

    test('digits masks a spaced card number as one run', () {
      const text = 'Card 4111 1111 1111 1111';
      expect(
        _substrings(text, PostHogTextMaskPolicies.digits()(text)),
        ['4111 1111 1111 1111'],
      );
    });

    test('digits masks separate numbers separately', () {
      const text = 'Order 2 of 5, ships 12 Sep';
      expect(
        _substrings(text, PostHogTextMaskPolicies.digits()(text)),
        ['2', '5', '12'],
      );
    });

    test('digits masks nothing in text without digits', () {
      const text = 'Send money';
      final mask = PostHogTextMaskPolicies.digits()(text);
      expect(mask, isA<PostHogTextMaskOnly>());
      expect(_substrings(text, mask), isEmpty);
    });

    test('redact masks every match of the pattern', () {
      const text = 'Sent to ada@example.com and bob@example.org';
      final policy =
          PostHogTextMaskPolicies.redact(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'));
      final mask = policy(text);
      expect(mask, isA<PostHogTextMaskOnly>());
      expect(_substrings(text, mask), ['ada@example.com', 'bob@example.org']);
    });

    test('reveal keeps only the matches visible', () {
      const text = 'Total NGN 5,000';
      final mask = PostHogTextMaskPolicies.reveal(RegExp('NGN'))(text);
      expect(mask, isA<PostHogTextMaskExcept>());
      expect(_substrings(text, mask), ['NGN']);
    });
  });

  group('textMaskPolicy in the widget tree', () {
    Future<void> setupPosthog({
      bool maskAllTexts = true,
      bool maskAllImages = true,
      PostHogTextMaskPolicy? policy,
    }) async {
      PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
      final config = PostHogConfig('test_project_token');
      config.sessionReplayConfig
        ..maskAllTexts = maskAllTexts
        ..maskAllImages = maskAllImages
        ..textMaskPolicy = policy;
      await Posthog().setup(config);
      // the controller singleton may have been created before this setup
      PostHogMaskController.instance.refreshParsers(config.sessionReplayConfig);
    }

    tearDown(() async {
      PostHogMaskController.instance.refreshParsers(null);
      await Posthog().close();
    });

    Future<void> pump(WidgetTester tester, Widget child,
        {double width = 320}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: PostHogMaskController.instance.containerKey,
            child: Scaffold(
              body: Center(child: SizedBox(width: width, child: child)),
            ),
          ),
        ),
      );
    }

    RenderObject container() =>
        PostHogMaskController.instance.containerKey.currentContext!
            .findRenderObject()!;

    /// The masks the capture pipeline would paint, in container coordinates.
    List<Rect> masks() {
      final config = Posthog().config!.sessionReplayConfig;
      final elements = PostHogMaskController.instance.getMaskElements(
        includeAllWidgets: config.masksAnyContent,
      )!;
      return [
        for (final e in elements)
          MatrixUtils.transformRect(e.transform ?? Matrix4.identity(), e.rect),
      ];
    }

    List<ElementData> maskElements() =>
        PostHogMaskController.instance.getMaskElements(
          includeAllWidgets: true,
        )!;

    // allRenderObjects can visit the same render object twice; dedupe by
    // identity before asserting there is exactly one match.
    RenderParagraph paragraph(WidgetTester tester, String containing) =>
        tester.allRenderObjects
            .whereType<RenderParagraph>()
            .where((p) => p.text.toPlainText().contains(containing))
            .toSet()
            .single;

    /// The on-screen box of [substring] within [renderObject]'s text, in
    /// container coordinates.
    Rect glyphs(RenderBox renderObject, String text, String substring) {
      final start = text.indexOf(substring);
      expect(start, isNonNegative, reason: '"$substring" not in "$text"');
      final selection = TextSelection(
        baseOffset: start,
        extentOffset: start + substring.length,
      );
      // Masks span the full line height: Flutter's max box style for a
      // paragraph, and the whole field for a single-line editable.
      final boxes = switch (renderObject) {
        RenderParagraph() => renderObject
            .getBoxesForSelection(
              selection,
              boxHeightStyle: ui.BoxHeightStyle.max,
            )
            .map((b) => b.toRect()),
        RenderEditable() => renderObject.getBoxesForSelection(selection).map(
              (b) =>
                  Rect.fromLTRB(b.left, 0, b.right, renderObject.size.height),
            ),
        _ => throw StateError('not a text render object'),
      };
      final local = boxes.reduce((a, b) => a.expandToInclude(b));
      return MatrixUtils.transformRect(
        renderObject.getTransformTo(container()),
        local,
      );
    }

    // Edge-inclusive, unlike Rect.contains, so a mask that equals the glyph
    // box exactly counts as covering it.
    bool covered(List<Rect> rects, Rect target) => rects.any(
          (r) =>
              r.left <= target.left + 0.5 &&
              r.top <= target.top + 0.5 &&
              r.right >= target.right - 0.5 &&
              r.bottom >= target.bottom - 0.5,
        );

    bool touched(List<Rect> rects, Rect target) =>
        rects.any((r) => r.overlaps(target.deflate(0.5)));

    testWidgets('digits masks only the amount in a Text', (tester) async {
      await setupPosthog(policy: PostHogTextMaskPolicies.digits());
      const text = 'Balance ₦2,450,000.00';
      await pump(tester, const Text(text));

      final p = paragraph(tester, 'Balance');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, text, '2,450,000.00'), epsilon: 0.5),
      );
      expect(touched(rects, glyphs(p, text, 'Balance')), isFalse);
    });

    testWidgets('applies to the spans of a RichText', (tester) async {
      await setupPosthog(policy: PostHogTextMaskPolicies.digits());
      await pump(
        tester,
        RichText(
          text: const TextSpan(
            style: TextStyle(color: _textColor),
            children: [
              TextSpan(text: 'Balance '),
              TextSpan(
                text: '₦2,450,000.00',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );

      final p = paragraph(tester, 'Balance');
      const text = 'Balance ₦2,450,000.00';
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, text, '2,450,000.00'), epsilon: 0.5),
      );
    });

    testWidgets('offsets stay aligned when a span has a semanticsLabel',
        (tester) async {
      await setupPosthog(policy: PostHogTextMaskPolicies.digits());
      await pump(
        tester,
        const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Total '),
            TextSpan(text: '1,200', semanticsLabel: 'one thousand two hundred'),
          ]),
        ),
      );

      final p = paragraph(tester, 'Total');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, 'Total 1,200', '1,200'), epsilon: 0.5),
      );
    });

    testWidgets('applies to the value of a non-sensitive text field',
        (tester) async {
      await setupPosthog(policy: PostHogTextMaskPolicies.digits());
      final controller = TextEditingController(text: 'Room 402');
      addTearDown(controller.dispose);
      await pump(tester, TextField(controller: controller));

      final editable =
          tester.allRenderObjects.whereType<RenderEditable>().toSet().single;
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(editable, 'Room 402', '402'), epsilon: 0.5),
      );
      expect(touched(rects, glyphs(editable, 'Room 402', 'Room')), isFalse);
    });

    testWidgets('a sensitive input is still masked in full', (tester) async {
      // A policy that would reveal everything must lose to the sensitivity
      // floor, which masks the input as whole blocks rather than per glyph.
      await setupPosthog(policy: (_) => const PostHogTextMask.none());
      final controller = TextEditingController(text: '1234');
      addTearDown(controller.dispose);
      await pump(tester, TextField(controller: controller, obscureText: true));

      final editable =
          tester.allRenderObjects.whereType<RenderEditable>().toSet().single;
      final editableInContainer = MatrixUtils.transformRect(
        editable.getTransformTo(container()),
        Offset.zero & editable.size,
      );
      final rects = masks();
      expect(covered(rects, editableInContainer), isTrue);
      final overlapping = rects.where((r) => r.overlaps(editableInContainer));
      expect(overlapping, isNotEmpty);
      expect(
        overlapping.every((r) => r.width >= editableInContainer.width - 0.5),
        isTrue,
        reason: 'the floor must not be split into partial rects',
      );
      expect(maskElements().any((e) => e.isSensitiveText), isTrue);
    });

    testWidgets('PostHogUnmaskWidget reveals a node the policy would mask',
        (tester) async {
      await setupPosthog(policy: PostHogTextMaskPolicies.digits());
      await pump(
        tester,
        const Column(children: [
          PostHogUnmaskWidget(child: Text('Reference 4411')),
          Text('Amount 9,000'),
        ]),
      );

      final revealed = paragraph(tester, 'Reference');
      final masked = paragraph(tester, 'Amount');
      final rects = masks();
      expect(
        touched(rects, glyphs(revealed, 'Reference 4411', '4411')),
        isFalse,
      );
      expect(
        covered(rects, glyphs(masked, 'Amount 9,000', '9,000')),
        isTrue,
      );
    });

    testWidgets('PostHogMaskWidget still masks a node the policy would reveal',
        (tester) async {
      await setupPosthog(policy: (_) => const PostHogTextMask.none());
      await pump(
        tester,
        const Column(children: [
          PostHogMaskWidget(child: Text('secret')),
          Text('visible'),
        ]),
      );

      final rects = masks();
      expect(
        covered(rects, glyphs(paragraph(tester, 'secret'), 'secret', 'secret')),
        isTrue,
      );
      expect(
        touched(
            rects, glyphs(paragraph(tester, 'visible'), 'visible', 'visible')),
        isFalse,
      );
    });

    testWidgets('the policy overrides maskAllTexts=true for text nodes',
        (tester) async {
      await setupPosthog(
        maskAllTexts: true,
        policy: (_) => const PostHogTextMask.none(),
      );
      await pump(tester, const Text('not masked'));
      expect(masks(), isEmpty);
    });

    testWidgets('all masks the node exactly once under maskAllTexts=true',
        (tester) async {
      await setupPosthog(
        maskAllTexts: true,
        policy: (_) => const PostHogTextMask.all(),
      );
      await pump(tester, const Text('secret'));

      final p = paragraph(tester, 'secret');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(
          MatrixUtils.transformRect(
              p.getTransformTo(container()), p.paintBounds),
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('except masks everything but the revealed range',
        (tester) async {
      await setupPosthog(policy: PostHogTextMaskPolicies.reveal(RegExp('NGN')));
      const text = 'Total NGN 5,000';
      await pump(
        tester,
        const Text(
          text,
          style: TextStyle(fontSize: 24, height: 1, color: _textColor),
        ),
      );

      final p = paragraph(tester, 'Total');
      final rects = masks();
      expect(touched(rects, glyphs(p, text, 'NGN')), isFalse);
      expect(covered(rects, glyphs(p, text, 'Total')), isTrue);
      expect(covered(rects, glyphs(p, text, '5,000')), isTrue);

      // Paint the masks the way ScreenshotCapturer does and check pixels.
      final revealedAt = glyphs(p, text, 'NGN').center;
      final maskedAt = glyphs(p, text, 'Total').center;
      final boundary = container() as RenderRepaintBoundary;
      final elements = maskElements();
      final (revealed, masked) = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(image, Offset.zero, Paint());
        ImageMaskPainter().drawMaskedImage(canvas, elements, 1);
        final maskedImage =
            await recorder.endRecording().toImage(image.width, image.height);
        final colors = (
          await _pixel(
              maskedImage, revealedAt.dx.round(), revealedAt.dy.round()),
          await _pixel(maskedImage, maskedAt.dx.round(), maskedAt.dy.round()),
        );
        image.dispose();
        maskedImage.dispose();
        return colors;
      }))!;
      expect(revealed, _textColor);
      expect(masked, _black);
    });

    testWidgets('a policy that throws masks the whole node', (tester) async {
      await setupPosthog(policy: (_) => throw StateError('boom'));
      await pump(tester, const Text('Balance 1,000'));

      final p = paragraph(tester, 'Balance');
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(
          MatrixUtils.transformRect(
              p.getTransformTo(container()), p.paintBounds),
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('a range outside the text masks the whole node',
        (tester) async {
      await setupPosthog(
        policy: (_) =>
            PostHogTextMask.only(const [TextRange(start: 0, end: 999)]),
      );
      await pump(tester, const Text('short'));

      final p = paragraph(tester, 'short');
      expect(
        masks().single,
        rectMoreOrLessEquals(
          MatrixUtils.transformRect(
              p.getTransformTo(container()), p.paintBounds),
          epsilon: 0.5,
        ),
      );
    });

    testWidgets('a range that wraps yields one rect per line', (tester) async {
      await setupPosthog(policy: PostHogTextMaskPolicies.digits());
      await pump(
        tester,
        const Text('4111 1111 1111 1111', style: TextStyle(fontSize: 20)),
        width: 120,
      );

      final p = paragraph(tester, '4111');
      final rects = masks();
      expect(rects.length, greaterThanOrEqualTo(2));
      final bounds = MatrixUtils.transformRect(
          p.getTransformTo(container()), p.paintBounds);
      for (final rect in rects) {
        expect(bounds.inflate(0.5).contains(rect.topLeft), isTrue);
        expect(bounds.inflate(0.5).contains(rect.bottomRight), isTrue);
      }
    });

    testWidgets('a policy alone turns the mask walk on', (tester) async {
      await setupPosthog(
        maskAllTexts: false,
        maskAllImages: false,
        policy: PostHogTextMaskPolicies.digits(),
      );
      await pump(tester, const Text('Ref 8802'));

      expect(Posthog().config!.sessionReplayConfig.masksAnyContent, isTrue);
      final p = paragraph(tester, 'Ref');
      expect(
        masks().single,
        rectMoreOrLessEquals(glyphs(p, 'Ref 8802', '8802'), epsilon: 0.5),
      );
    });

    testWidgets('a policy set at runtime applies on the next walk',
        (tester) async {
      await setupPosthog(maskAllTexts: true);
      const text = 'Balance 1,000';
      await pump(tester, const Text(text));

      final p = paragraph(tester, 'Balance');
      final whole = MatrixUtils.transformRect(
          p.getTransformTo(container()), p.paintBounds);
      expect(covered(masks(), whole), isTrue);

      Posthog().config!.sessionReplayConfig.textMaskPolicy =
          PostHogTextMaskPolicies.digits();
      final rects = masks();
      expect(rects, hasLength(1));
      expect(
        rects.single,
        rectMoreOrLessEquals(glyphs(p, text, '1,000'), epsilon: 0.5),
      );
    });
  });
}
