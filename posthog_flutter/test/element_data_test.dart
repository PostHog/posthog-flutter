import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

ElementData _node(String type, {List<ElementData>? children, Widget? widget}) {
  return ElementData(
    rect: const Rect.fromLTWH(0, 0, 10, 10),
    type: type,
    children: children,
    widget: widget,
  );
}

List<String> _types(List<ElementData> elements) =>
    elements.map((e) => e.type).toList();

/// Mask rects are local paint bounds plus a transform to the capture
/// container, which is what ImageMaskPainter draws with.
Rect _resolved(ElementData element) => MatrixUtils.transformRect(
    element.transform ?? Matrix4.identity(), element.rect);

bool _covers(List<ElementData> elements, Rect target) {
  return elements.any((element) {
    final rect = _resolved(element);
    return rect.left <= target.left &&
        rect.top <= target.top &&
        rect.right >= target.right &&
        rect.bottom >= target.bottom;
  });
}

Future<void> _pumpMaskedApp(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    PostHogWidget(
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ElementData.extractRects', () {
    test('returns every descendant of a deeply nested tree', () {
      final root = _node('Root', children: [
        _node('a', children: [
          _node('b', children: [
            _node('c', children: [_node('d')]),
          ]),
        ]),
      ]);

      expect(_types(root.extractRects()), ['a', 'b', 'c', 'd']);
    });

    test('returns direct children when the tree is flat', () {
      final root = _node('Root', children: [_node('a'), _node('b')]);

      expect(_types(root.extractRects()), ['a', 'b']);
    });

    test('keeps a node that has several children alongside the children', () {
      final root = _node('Root', children: [
        _node('parent', children: [_node('a'), _node('b')]),
      ]);

      expect(_types(root.extractRects()), ['parent', 'a', 'b']);
    });

    test('returns nothing for a childless root', () {
      expect(_node('Root').extractRects(), isEmpty);
    });
  });

  group('ElementData.extractMaskWidgetRects', () {
    test('collects mask widgets and obscured fields at any depth', () {
      final root = _node('Root', children: [
        _node('Padding', children: [
          _node('PostHogMaskWidget',
              widget: const PostHogMaskWidget(child: SizedBox()),
              children: [
                _node('TextField',
                    widget: const TextField(obscureText: true),
                    children: [
                      _node('Text', widget: const Text('visible')),
                    ]),
              ]),
        ]),
      ]);

      expect(_types(root.extractMaskWidgetRects()),
          ['PostHogMaskWidget', 'TextField']);
    });

    test('ignores fields that are not obscured', () {
      final root = _node('Root', children: [
        _node('TextField', widget: const TextField(obscureText: false)),
      ]);

      expect(root.extractMaskWidgetRects(), isEmpty);
    });
  });

  group('masking a real widget tree', () {
    testWidgets('masks the whole PostHogMaskWidget, not just its text children',
        (tester) async {
      // The avatar matches no masking rule of its own, so it is only covered
      // if the wrapper contributes its own rect.
      await _pumpMaskedApp(
        tester,
        PostHogMaskWidget(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Jane Doe'),
              Container(
                key: const Key('avatar'),
                width: 48,
                height: 48,
                color: Colors.amber,
              ),
              const Text('Balance: 1234'),
            ],
          ),
        ),
      );

      final elements =
          PostHogMaskController.instance.getCurrentWidgetsElements()!;

      expect(_covers(elements, tester.getRect(find.byKey(const Key('avatar')))),
          isTrue);
    });

    testWidgets('masks a RichText', (tester) async {
      await _pumpMaskedApp(
        tester,
        RichText(
          text: const TextSpan(
            style: TextStyle(fontSize: 16, color: Colors.black),
            children: [
              TextSpan(text: 'This is '),
              TextSpan(text: 'sensitive data'),
            ],
          ),
        ),
      );

      final elements =
          PostHogMaskController.instance.getCurrentWidgetsElements()!;

      expect(_covers(elements, tester.getRect(find.byType(RichText))), isTrue);
    });

    testWidgets('masks a SelectableText', (tester) async {
      await _pumpMaskedApp(
        tester,
        const SelectableText('This SelectableText should also be masked'),
      );

      final elements =
          PostHogMaskController.instance.getCurrentWidgetsElements()!;

      expect(_covers(elements, tester.getRect(find.byType(SelectableText))),
          isTrue);
    });

    testWidgets('still masks a plain Text', (tester) async {
      await _pumpMaskedApp(tester, const Text('plain text'));

      final elements =
          PostHogMaskController.instance.getCurrentWidgetsElements()!;

      expect(_covers(elements, tester.getRect(find.byType(Text))), isTrue);
    });

    testWidgets('still masks a TextField', (tester) async {
      await _pumpMaskedApp(tester, const TextField());

      final elements =
          PostHogMaskController.instance.getCurrentWidgetsElements()!;

      expect(
          _covers(elements, tester.getRect(find.byType(EditableText))), isTrue);
    });

    testWidgets('does not mask a sibling that matched no rule', (tester) async {
      await _pumpMaskedApp(
        tester,
        SizedBox(
          width: 400,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('secret'),
              Container(
                key: const Key('plain'),
                width: 48,
                height: 48,
                color: Colors.amber,
              ),
            ],
          ),
        ),
      );

      final elements =
          PostHogMaskController.instance.getCurrentWidgetsElements()!;
      final plain = tester.getRect(find.byKey(const Key('plain')));

      expect(elements.any((e) => _resolved(e).overlaps(plain)), isFalse);
    });
  });
}
