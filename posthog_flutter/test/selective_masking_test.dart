import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';

import 'posthog_flutter_platform_interface_fake.dart';

Future<void> _setup(
    {bool maskAllTexts = true, bool maskAllImages = true}) async {
  PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
  final config = PostHogConfig('test_project_token');
  config.sessionReplayConfig
    ..maskAllTexts = maskAllTexts
    ..maskAllImages = maskAllImages;
  await Posthog().setup(config);
  PostHogMaskController.instance.refreshParsers(config.sessionReplayConfig);
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RepaintBoundary(
        key: PostHogMaskController.instance.containerKey,
        child: SizedBox(width: 400, child: child),
      ),
    ),
  ));
}

List<ElementData> _masks() {
  final config = Posthog().config!.sessionReplayConfig;
  return PostHogMaskController.instance.getMaskElements(
    includeAllWidgets: config.maskAllTexts || config.maskAllImages,
  )!;
}

Rect _rect(ElementData element) => MatrixUtils.transformRect(
    element.transform ?? Matrix4.identity(), element.rect);

bool _isMasked(Rect target) => _masks().any((e) => _rect(e).overlaps(target));

class _SafeLabel extends StatelessWidget {
  const _SafeLabel();

  @override
  Widget build(BuildContext context) => const PostHogUnmaskWidget(
        child: Text('safe label'),
      );
}

void main() {
  tearDown(() async {
    PostHogMaskController.instance.refreshParsers(null);
    await Posthog().close();
  });

  for (final maskAllImages in [false, true]) {
    for (final signal in [
      'obscureText',
      'visiblePassword',
      AutofillHints.password,
      AutofillHints.newPassword,
      AutofillHints.creditCardNumber,
      AutofillHints.creditCardSecurityCode,
      AutofillHints.oneTimeCode,
    ]) {
      for (final kind in ['Material', 'Form', 'Cupertino', 'Editable']) {
        testWidgets(
            '$kind $signal stays masked with texts=false, images=$maskAllImages',
            (tester) async {
          await _setup(maskAllTexts: false, maskAllImages: maskAllImages);
          final controller = TextEditingController(text: '4111111111111111');
          final focusNode = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focusNode.dispose);
          final obscure = signal == 'obscureText';
          final keyboardType = signal == 'visiblePassword'
              ? TextInputType.visiblePassword
              : TextInputType.text;
          final hints = signal == 'obscureText' || signal == 'visiblePassword'
              ? null
              : [signal];
          final Widget field;
          switch (kind) {
            case 'Material':
              field = TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  autofillHints: hints);
            case 'Form':
              field = TextFormField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  autofillHints: hints);
            case 'Cupertino':
              field = CupertinoTextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  autofillHints: hints);
            default:
              field = EditableText(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 16),
                  cursorColor: Colors.blue,
                  backgroundCursorColor: Colors.grey,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  autofillHints: hints);
          }
          await _pump(tester, field);
          final editable = tester.renderObject<RenderEditable>(
              find.byElementPredicate((element) =>
                  element is RenderObjectElement &&
                  element.renderObject is RenderEditable));
          final target = MatrixUtils.transformRect(
              editable.getTransformTo(PostHogMaskController
                  .instance.containerKey.currentContext!
                  .findRenderObject()),
              Rect.fromLTWH(
                  0, 0, editable.size.width, editable.preferredLineHeight));
          expect(
              _masks().any((e) =>
                  _rect(e).contains(target.topLeft) &&
                  _rect(e).right >= target.right &&
                  _rect(e).bottom >= target.bottom),
              isTrue);
        });
      }
    }
  }

  testWidgets(
      'unmasks text, rich text, selectable text and ordinary inputs only in its subtree',
      (tester) async {
    await _setup();
    await _pump(
        tester,
        Column(children: [
          const Text('private sibling'),
          PostHogUnmaskWidget(
              child: Column(children: [
            const Text('safe text'),
            RichText(text: const TextSpan(text: 'safe rich text')),
            const SelectableText('safe selectable text'),
            const TextField(),
          ])),
        ]));
    expect(_isMasked(tester.getRect(find.text('private sibling'))), isTrue);
    for (final text in [
      'safe text',
      'safe rich text',
      'safe selectable text'
    ]) {
      expect(
          _isMasked(tester.getRect(find.text(text, findRichText: true).first)),
          isFalse,
          reason: text);
    }
    expect(_isMasked(tester.getRect(find.byType(TextField))), isFalse);
  });

  testWidgets('a forwarding ancestor must not mask a nested unmask widget',
      (tester) async {
    await _setup();
    await _pump(tester, const _SafeLabel());
    expect(_masks(), isEmpty);
  });

  testWidgets('unmasking images does not unmask sibling images',
      (tester) async {
    await _setup();
    final ui.Image image =
        (await tester.runAsync(() => createTestImage(width: 20, height: 20)))!;
    addTearDown(image.dispose);
    await _pump(
        tester,
        Row(children: [
          RawImage(
              key: const Key('private image'),
              image: image,
              width: 20,
              height: 20),
          PostHogUnmaskWidget(
              child: RawImage(
                  key: const Key('safe image'),
                  image: image,
                  width: 20,
                  height: 20)),
        ]));
    expect(_isMasked(tester.getRect(find.byKey(const Key('private image')))),
        isTrue);
    expect(_isMasked(tester.getRect(find.byKey(const Key('safe image')))),
        isFalse);
  });

  for (final maskOutside in [false, true]) {
    testWidgets('explicit mask wins with maskOutside=$maskOutside',
        (tester) async {
      await _setup();
      const text = Text('private');
      final child = maskOutside
          ? const PostHogMaskWidget(child: PostHogUnmaskWidget(child: text))
          : const PostHogUnmaskWidget(
              child:
                  PostHogMaskWidget(child: PostHogUnmaskWidget(child: text)));
      await _pump(tester, child);
      expect(_isMasked(tester.getRect(find.text('private'))), isTrue);
    });
  }

  for (final maskAllTexts in [false, true]) {
    testWidgets(
        'sensitive fields stay masked inside unmask with texts=$maskAllTexts',
        (tester) async {
      await _setup(maskAllTexts: maskAllTexts, maskAllImages: false);
      await _pump(
          tester,
          PostHogUnmaskWidget(
              child: Column(children: [
            const Text('safe'),
            const TextField(obscureText: true),
            const CupertinoTextField(
                autofillHints: [AutofillHints.creditCardNumber]),
            TextFormField(keyboardType: TextInputType.visiblePassword),
          ])));
      expect(_isMasked(tester.getRect(find.text('safe'))), isFalse);
      for (final element in find.byType(EditableText).evaluate()) {
        expect(
            _isMasked(tester.getRect(find.byWidget(element.widget))), isTrue);
      }
    });
  }

  testWidgets('updates masking when an unmask wrapper is added or removed',
      (tester) async {
    await _setup();
    for (final reveal in [false, true, false]) {
      await _pump(
          tester,
          reveal
              ? const PostHogUnmaskWidget(child: Text('label'))
              : const Text('label'));
      expect(_isMasked(tester.getRect(find.text('label'))), !reveal);
    }
  });

  testWidgets('sensitive input masking covers scaled text in a dense field',
      (tester) async {
    await _setup(maskAllTexts: false, maskAllImages: false);
    await _pump(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: const PostHogUnmaskWidget(
              child: SizedBox(
                  height: 30,
                  child: TextField(
                    style: TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                        isDense: true, contentPadding: EdgeInsets.zero),
                    autofillHints: [AutofillHints.creditCardNumber],
                  ))),
        ));
    final editable = tester.renderObject<RenderEditable>(
        find.byElementPredicate((element) =>
            element is RenderObjectElement &&
            element.renderObject is RenderEditable));
    final target = MatrixUtils.transformRect(
        editable.getTransformTo(PostHogMaskController
            .instance.containerKey.currentContext!
            .findRenderObject()),
        Rect.fromLTWH(0, 0, editable.size.width, editable.preferredLineHeight));
    expect(
        _masks().any((e) =>
            _rect(e).top <= target.top &&
            _rect(e).left <= target.left &&
            _rect(e).right >= target.right &&
            _rect(e).bottom >= target.bottom),
        isTrue);
  });

  testWidgets('checks every autofill hint and updates sensitivity on rebuild',
      (tester) async {
    await _setup(maskAllTexts: false, maskAllImages: false);
    for (final hints in [
      [AutofillHints.username],
      [AutofillHints.username, AutofillHints.oneTimeCode],
      [AutofillHints.username],
    ]) {
      await _pump(
          tester, PostHogUnmaskWidget(child: TextField(autofillHints: hints)));
      expect(_masks().isNotEmpty, hints.contains(AutofillHints.oneTimeCode));
    }
  });

  for (final pixelRatio in [1.0, 2.0]) {
    testWidgets(
        'captured pixels reveal only safe content at pixelRatio=$pixelRatio',
        (tester) async {
      await _setup();
      final controller = TextEditingController(text: '4111111111111111');
      addTearDown(controller.dispose);
      await _pump(
          tester,
          PostHogUnmaskWidget(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Safe error message',
                  style: TextStyle(
                      color: Colors.red, backgroundColor: Colors.yellow)),
              TextField(
                  controller: controller,
                  autofillHints: const [AutofillHints.creditCardNumber]),
              const PostHogMaskWidget(child: Text('private label')),
            ],
          )));
      final boundary = PostHogMaskController
          .instance.containerKey.currentContext!
          .findRenderObject()! as RenderRepaintBoundary;
      final safeRect = tester.getRect(find.text('Safe error message'));
      final sensitiveRect = tester.getRect(find.byType(EditableText));
      final privateRect = tester.getRect(find.text('private label'));
      final masks = _masks();
      await tester.runAsync(() async {
        final source = await boundary.toImage(pixelRatio: pixelRatio);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)
          ..drawImage(source, Offset.zero, Paint());
        ImageMaskPainter().drawMaskedImage(canvas, masks, pixelRatio);
        final picture = recorder.endRecording();
        final masked = await picture.toImage(source.width, source.height);
        try {
          final sourceBytes =
              (await source.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          final maskedBytes =
              (await masked.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          for (final rect in [safeRect, sensitiveRect, privateRect]) {
            var changed = false;
            for (var y = (rect.top * pixelRatio).ceil() + 1;
                y < (rect.bottom * pixelRatio).floor() - 1;
                y++) {
              for (var x = (rect.left * pixelRatio).ceil() + 1;
                  x < (rect.right * pixelRatio).floor() - 1;
                  x++) {
                final i = (y * source.width + x) * 4;
                final actual = maskedBytes.sublist(i, i + 4);
                final original = sourceBytes.sublist(i, i + 4);
                if (rect == safeRect) {
                  expect(actual, original, reason: 'safe content at ($x, $y)');
                } else {
                  expect(actual, [0, 0, 0, 255],
                      reason: 'private content at ($x, $y)');
                  changed |=
                      original[0] != 0 || original[1] != 0 || original[2] != 0;
                }
              }
            }
            if (rect != safeRect) expect(changed, isTrue);
          }
        } finally {
          source.dispose();
          masked.dispose();
          picture.dispose();
        }
      });
    });
  }

  testWidgets('ordinary inputs remain visible when global text masking is off',
      (tester) async {
    await _setup(maskAllTexts: false, maskAllImages: false);
    await _pump(
        tester, const TextField(autofillHints: [AutofillHints.username]));
    expect(_masks(), isEmpty);
  });
}
