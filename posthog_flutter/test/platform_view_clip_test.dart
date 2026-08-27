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
}
