import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_widget.dart';

void main() {
  test('Benchmark extractMaskWidgetRects', () {
    // Build a large tree of ElementData
    final root = ElementData(
      rect: const Rect.fromLTWH(0, 0, 1000, 1000),
      type: 'root',
      children: [],
    );

    int count = 0;

    // Fan out 4, Depth 6 -> 4^6 = 4096 leaves, total ~5500 nodes.
    void addChildren(ElementData parent, int depth) {
      if (depth >= 6) return;

      for (int i = 0; i < 4; i++) {
        count++;
        // Unique rects
        final rect = Rect.fromLTWH(
          count.toDouble(),
          count.toDouble(),
          50,
          50
        );

        Widget? widget;
        // Add about 1/3 of them
        if (count % 3 == 0) {
          widget = const PostHogMaskWidget(child: SizedBox());
        } else if (count % 3 == 1) {
          widget = const TextField(obscureText: true);
        } else {
          widget = const SizedBox();
        }

        final child = ElementData(
          rect: rect,
          type: 'child',
          widget: widget,
          children: [],
        );

        parent.addChildren(child);
        addChildren(child, depth + 1);
      }
    }

    addChildren(root, 0);
    print('Created tree with approx $count elements.');

    final stopwatch = Stopwatch()..start();

    // Run it multiple times to get a stable measurement
    final int iterations = 5;
    for (int i = 0; i < iterations; i++) {
      root.extractMaskWidgetRects();
    }

    stopwatch.stop();
    print('Time taken for $iterations iterations: ${stopwatch.elapsedMilliseconds} ms');
    print('Average time per iteration: ${stopwatch.elapsedMilliseconds / iterations} ms');
  });
}
