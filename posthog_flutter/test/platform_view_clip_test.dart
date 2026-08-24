import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

void main() {
  group('clippedPaintBounds — ancestor clip intersection', () {
    testWidgets('an unclipped view keeps its full paint bounds',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: Key('ancestor'),
              width: 300,
              height: 300,
              child: Center(
                child: SizedBox(key: Key('view'), width: 200, height: 200),
              ),
            ),
          ),
        ),
      );

      final view =
          tester.renderObject<RenderBox>(find.byKey(const Key('view')));
      final ancestor =
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor')));

      expect(clippedPaintBounds(view, ancestor),
          const Rect.fromLTWH(0, 0, 200, 200));
    });

    testWidgets('a ClipRect ancestor trims the view to the visible region',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: Key('ancestor'),
              width: 100,
              height: 100,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxWidth: 300,
                  maxHeight: 300,
                  child: SizedBox(key: Key('view'), width: 300, height: 300),
                ),
              ),
            ),
          ),
        ),
      );

      final view =
          tester.renderObject<RenderBox>(find.byKey(const Key('view')));
      final ancestor =
          tester.renderObject<RenderBox>(find.byKey(const Key('ancestor')));

      // The view paints 300x300 but the ClipRect only shows the top-left 100x100.
      expect(clippedPaintBounds(view, ancestor),
          const Rect.fromLTWH(0, 0, 100, 100));
    });
  });
}
