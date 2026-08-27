import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

void main() {
  group('clippedPaintBounds', () {
    testWidgets('an unclipped view keeps its full paint bounds',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: Key('ancestor'),
              width: 300,
              height: 300,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(key: Key('view'), width: 200, height: 200),
              ),
            ),
          ),
        ),
      );

      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        const Rect.fromLTWH(0, 0, 200, 200),
      );
    });

    testWidgets('a ClipRect ancestor trims the view to its visible region',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: Key('ancestor'),
              width: 100,
              height: 100,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: 300,
                  maxHeight: 300,
                  child: SizedBox(key: Key('view'), width: 300, height: 300),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
    });

    testWidgets('a farther ancestor clip is applied, not just the nearest',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: Key('ancestor'),
              width: 300,
              height: 300,
              // The outer clip (60) is tighter than the nearest one (80), so a
              // result of 60 proves the walk kept going past the first clip.
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  height: 60,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minHeight: 0,
                      maxHeight: 300,
                      child: SizedBox(
                        height: 80,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minHeight: 0,
                            maxHeight: 300,
                            child: SizedBox(
                                key: Key('view'), width: 300, height: 300),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ).height,
        60,
      );
    });

    testWidgets('a clip is mapped through a non-zero ancestor offset',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: Key('ancestor'),
              width: 600,
              height: 600,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: ClipRect(
                    child: Padding(
                      padding: EdgeInsets.only(left: 50, top: 100),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        minHeight: 0,
                        maxWidth: 400,
                        maxHeight: 400,
                        child:
                            SizedBox(key: Key('view'), width: 400, height: 400),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // The clip is 300x300 in the ClipRect's space but the view sits at
      // (50, 100) inside it, so in the view's own space only 250x200 survives.
      // Using the forward transform instead of its inverse would give
      // (50, 100, 350, 400) here.
      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        const Rect.fromLTWH(0, 0, 250, 200),
      );
    });

    testWidgets('a null ancestor walks to the root without throwing',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(key: Key('view'), width: 50, height: 50),
          ),
        ),
      );

      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          null,
        ),
        const Rect.fromLTWH(0, 0, 50, 50),
      );
    });
  });

  group('clippedPaintBounds — scroll viewport', () {
    // RenderViewportBase.describeApproximatePaintClip is a different framework
    // implementation from RenderCustomClip, and a scrolled view is the only
    // case that produces a non-zero origin.
    Widget list(ScrollController controller) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 300,
              height: 300,
              child: ListView(
                controller: controller,
                children: const [
                  SizedBox(height: 250),
                  SizedBox(key: Key('view'), width: 300, height: 200),
                  SizedBox(height: 400),
                ],
              ),
            ),
          ),
        );

    Rect boundsOf(WidgetTester tester) => clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        );

    testWidgets('a view straddling the bottom edge keeps only the visible band',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(list(controller));

      expect(boundsOf(tester), const Rect.fromLTRB(0, 0, 300, 50));
    });

    testWidgets('a view straddling the top edge is trimmed from its origin',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(list(controller));

      controller.jumpTo(400);
      await tester.pump();

      expect(boundsOf(tester), const Rect.fromLTRB(0, 150, 300, 200));
    });
  });

  group('clippedPaintBounds — projective ancestors', () {
    testWidgets(
        'a perspective ancestor keeps the full bounds, not a shrunk one',
        (tester) async {
      // Mapping a rect through the inverse of a projective matrix by its four
      // corners can produce a far smaller rect than the real one, which would
      // silently shrink or drop the mask.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 400,
              height: 400,
              child: ClipRect(
                child: Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.004)
                    ..rotateX(1.4),
                  child:
                      const SizedBox(key: Key('view'), width: 200, height: 200),
                ),
              ),
            ),
          ),
        ),
      );

      final view =
          tester.renderObject<RenderBox>(find.byKey(const Key('view')));
      expect(
        clippedPaintBounds(
          view,
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        view.paintBounds,
      );
    });

    testWidgets('a ListWheelScrollView item keeps a non-empty mask rect',
        (tester) async {
      // CupertinoPicker's viewport applies a per-child perspective transform
      // and reports a clip, so its items hit the projective path in ordinary use.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 400,
              height: 400,
              child: ListWheelScrollView(
                itemExtent: 120,
                children: List.generate(
                  7,
                  (i) => SizedBox(key: Key('i$i'), width: 300, height: 120),
                ),
              ),
            ),
          ),
        ),
      );

      final ancestor =
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor')));
      // Only the items the wheel actually builds are on screen.
      for (final key in ['i1', 'i2']) {
        final item = tester.renderObject<RenderBox>(find.byKey(Key(key)));
        expect(clippedPaintBounds(item, ancestor).isEmpty, isFalse,
            reason: '$key is on screen and must keep a mask');
      }
    });
  });

  group('clippedPaintBounds — failing and degenerate clips', () {
    testWidgets('a clipper that throws leaves the full paint bounds',
        (tester) async {
      // RenderCustomClip asks getApproximateClipRect, not getClip, so a clipper
      // that throws from getClip never reaches the walk and would prove nothing.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 300,
              height: 300,
              child: ClipRect(
                clipper: _ThrowingApproxClipper(),
                child:
                    const SizedBox(key: Key('view'), width: 300, height: 300),
              ),
            ),
          ),
        ),
      );

      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        const Rect.fromLTWH(0, 0, 300, 300),
      );
    });

    testWidgets('the same clipper not throwing reports its narrow clip',
        (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 300,
              height: 300,
              child: ClipRect(
                clipper: _NarrowClipper(),
                child:
                    const SizedBox(key: Key('view'), width: 300, height: 300),
              ),
            ),
          ),
        ),
      );

      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
    });

    testWidgets('a view clipped entirely away reports an empty rect',
        (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 300,
              height: 300,
              child: ClipRect(
                child: Transform.translate(
                  offset: const Offset(1000, 1000),
                  child:
                      const SizedBox(key: Key('view'), width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );

      final bounds = clippedPaintBounds(
        tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
        tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
      );
      expect(bounds.isEmpty, isTrue);
      expect(bounds, Rect.zero);
    });
  });
}

class _ThrowingApproxClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => const Rect.fromLTWH(0, 0, 100, 100);

  @override
  Rect getApproximateClipRect(Size size) => throw StateError('from app code');

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// The non-throwing control for [_ThrowingApproxClipper]: identical shape, so
/// the narrow rect here proves the throwing case really did fall back.
class _NarrowClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => const Rect.fromLTWH(0, 0, 100, 100);

  @override
  Rect getApproximateClipRect(Size size) => getClip(size);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
