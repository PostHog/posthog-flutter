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

  group('maskRectCoveringMotion', () {
    final identity = Matrix4.identity();

    test('a still view keeps exactly its collected rect', () {
      const collected = Rect.fromLTWH(0, 0, 200, 100);
      expect(maskRectCoveringMotion(collected, identity, collected, identity),
          collected);
    });

    test('a view that scrolled is covered at both positions', () {
      const collected = Rect.fromLTWH(0, 0, 200, 100);
      expect(
        maskRectCoveringMotion(collected, identity, collected,
            Matrix4.translationValues(0, -40, 0)),
        const Rect.fromLTWH(0, -40, 200, 140),
      );
    });

    test('a shrinking clip still covers the larger collected rect', () {
      const collected = Rect.fromLTWH(0, 0, 200, 100);
      expect(
        maskRectCoveringMotion(
            collected, identity, const Rect.fromLTWH(0, 0, 200, 40), identity),
        collected,
      );
    });

    test('a non-invertible transform falls back to the collected rect', () {
      const collected = Rect.fromLTWH(0, 0, 200, 100);
      expect(
        maskRectCoveringMotion(collected, Matrix4.zero(), collected, identity),
        collected,
      );
    });
  });
}
