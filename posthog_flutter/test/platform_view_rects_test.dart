import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

/// A platform view with no native side, so the walk sees a real
/// [PlatformViewRenderBox] without a platform channel behind it.
class _FakePlatformView extends LeafRenderObjectWidget {
  final double width;
  final double height;
  const _FakePlatformView({required this.width, required this.height});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      PlatformViewRenderBox(
        controller: _FakeController(),
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        gestureRecognizers: const {},
      );
}

class _FakeController extends PlatformViewController {
  @override
  int get viewId => 0;
  @override
  Future<void> clearFocus() async {}
  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}
  @override
  Future<void> dispose() async {}
}

Widget _clippedView({required double clipHeight, required double viewHeight}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: PostHogWidget(
        child: Align(
          alignment: Alignment.topLeft,
          child: ClipRect(
            child: SizedBox(
              width: 100,
              height: clipHeight,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: 0,
                maxHeight: viewHeight,
                child: SizedBox(
                  width: 100,
                  height: viewHeight,
                  child: const _FakePlatformView(width: 100, height: 0),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  late ScreenshotCapturer capturer;

  setUp(() => capturer = ScreenshotCapturer(PostHogConfig('test')));

  testWidgets('a masked platform view is masked to its visible region',
      (tester) async {
    await tester.pumpWidget(_clippedView(clipHeight: 100, viewHeight: 300));
    final rects =
        capturer.debugPlatformViewRects(PostHogPlatformViewPrivacy.mask);
    expect(rects, isNotNull);
    expect(rects!.masked, [const Rect.fromLTWH(0, 0, 100, 100)]);
    expect(rects.revealed, isEmpty);
  });

  testWidgets('a revealed platform view carries its visible region',
      (tester) async {
    await tester.pumpWidget(_clippedView(clipHeight: 100, viewHeight: 300));
    final rects =
        capturer.debugPlatformViewRects(PostHogPlatformViewPrivacy.capture);
    expect(rects, isNotNull);
    expect(rects!.masked, isEmpty);
    expect(rects.revealed, [const Rect.fromLTWH(0, 0, 100, 100)]);
  });

  testWidgets('a fully clipped platform view is dropped, not masked at zero',
      (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PostHogWidget(
          child: Align(
            alignment: Alignment.topLeft,
            child: ClipRect(
              child: SizedBox(
                width: 100,
                height: 100,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: 300,
                  child: Transform.translate(
                    offset: const Offset(0, 200),
                    child: const SizedBox(
                      width: 100,
                      height: 100,
                      child: _FakePlatformView(width: 100, height: 100),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final rects =
        capturer.debugPlatformViewRects(PostHogPlatformViewPrivacy.mask);
    expect(rects, isNotNull);
    expect(rects!.masked, isEmpty);
  });

  testWidgets('a masked view that cannot be measured drops the frame',
      (tester) async {
    // The container the walk measures against sits in a detached tree, so
    // getTransformTo throws "not in the same render tree".
    final detached = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints.tightFor(width: 1));
    addTearDown(detached.dispose);
    await tester.pumpWidget(_clippedView(clipHeight: 100, viewHeight: 300));

    expect(
      capturer.debugPlatformViewRectsAgainst(
          PostHogPlatformViewPrivacy.mask, detached),
      isNull,
    );
    // A revealed view has no mask to lose, so the frame still ships.
    expect(
      capturer.debugPlatformViewRectsAgainst(
          PostHogPlatformViewPrivacy.capture, detached),
      isNotNull,
    );
  });
}
