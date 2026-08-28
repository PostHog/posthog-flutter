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

  group('clippedPaintBounds — overlapping sliver header', () {
    testWidgets('a pinned header trims the band it covers', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 300,
              height: 300,
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  const SliverPersistentHeader(
                      pinned: true, delegate: _PinnedHeader()),
                  SliverToBoxAdapter(
                    child: Container(
                        key: const Key('view'), height: 200, color: null),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 800)),
                ],
              ),
            ),
          ),
        ),
      );

      controller.jumpTo(100);
      await tester.pump();

      // The viewport excludes the band the header covers. That is right for an
      // opaque header, and masking it would black the header out of the replay;
      // a translucent header leaves the band visible and unmasked.
      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        const Rect.fromLTRB(0, 100, 300, 200),
      );
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

    testWidgets('perspective reached only through the third term still guards',
        (tester) async {
      // Rotating outside a perspective transform leaves storage[3] and [7] zero
      // and only storage[11] set, so dropping that term would shrink the mask.
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
                  transform: Matrix4.rotationX(1.2),
                  child: Transform(
                    transform: Matrix4.identity()..setEntry(3, 2, 0.01),
                    child: const SizedBox(
                        key: Key('view'), width: 200, height: 200),
                  ),
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
    testWidgets('an under-reporting ClipRRect clipper does not shrink the mask',
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
              child: ClipRRect(
                clipper: _UnderReportingRRectClipper(),
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

    testWidgets('an under-reporting ClipPath clipper does not shrink the mask',
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
              child: ClipPath(
                clipper: _UnderReportingPathClipper(),
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

    testWidgets('a clipper returning a non-finite rect leaves the full bounds',
        (tester) async {
      // A NaN rect is not empty, so an unguarded walk would carry it into the
      // mask geometry and the mask would never be drawn.
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
                clipper: _NaNClipper(),
                child:
                    const SizedBox(key: Key('view'), width: 300, height: 300),
              ),
            ),
          ),
        ),
      );
      tester.takeException();

      expect(
        clippedPaintBounds(
          tester.renderObject<RenderBox>(find.byKey(const Key('view'))),
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor'))),
        ),
        const Rect.fromLTWH(0, 0, 300, 300),
      );
    });

    testWidgets('a clipper attached with Clip.none does not shrink the mask',
        (tester) async {
      // Flutter paints the view in full, so the clipper describes nothing.
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
                clipBehavior: Clip.none,
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

    testWidgets('an under-reporting clipper does not shrink the mask',
        (tester) async {
      // getApproximateClipRect may report less than the clipper actually clips
      // to; masking the smaller rect would leave the difference uncovered.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: const Key('ancestor'),
              width: 400,
              height: 400,
              // Offset so the clip's frame differs from the ancestor's, which
              // a walk measuring against the wrong node would not notice.
              child: Padding(
                padding: const EdgeInsets.only(left: 40, top: 60),
                child: ClipRect(
                  clipper: _UnderReportingClipper(),
                  child:
                      const SizedBox(key: Key('view'), width: 300, height: 300),
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

    testWidgets('a clipper that throws leaves the full paint bounds',
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
                clipper: _ThrowingApproxClipper(),
                child:
                    const SizedBox(key: Key('view'), width: 300, height: 300),
              ),
            ),
          ),
        ),
      );

      // The framework hits the same throw while painting the clip; that is the
      // app's own bug, and it must not stop the mask from being computed.
      expect(tester.takeException(), isStateError);

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
  Rect getClip(Size size) => throw StateError('from app code');

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// Reports far less than it clips to, which is legal and would under-mask.
class _UnderReportingClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => const Rect.fromLTWH(0, 0, 100, 100);

  @override
  Rect getApproximateClipRect(Size size) => const Rect.fromLTWH(0, 0, 10, 10);

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

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  const _PinnedHeader();

  @override
  double get minExtent => 80;

  @override
  double get maxExtent => 80;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      const SizedBox.expand();

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class _UnderReportingRRectClipper extends CustomClipper<RRect> {
  @override
  RRect getClip(Size size) =>
      RRect.fromRectXY(const Rect.fromLTWH(0, 0, 100, 100), 8, 8);

  @override
  Rect getApproximateClipRect(Size size) => const Rect.fromLTWH(0, 0, 10, 10);

  @override
  bool shouldReclip(covariant CustomClipper<RRect> oldClipper) => false;
}

class _UnderReportingPathClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) =>
      Path()..addRect(const Rect.fromLTWH(0, 0, 100, 100));

  @override
  Rect getApproximateClipRect(Size size) => const Rect.fromLTWH(0, 0, 10, 10);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _NaNClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(double.nan, 0, 100, 100);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
