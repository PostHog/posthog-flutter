import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

void main() {
  Widget appWithContainerKey() {
    return MaterialApp(
      home: RepaintBoundary(
        key: PostHogMaskController.instance.containerKey,
        child: Scaffold(
          body: Column(
            children: [
              const Text('visible text'),
              PostHogMaskWidget(child: const Text('wrapped')),
              const TextField(obscureText: true),
            ],
          ),
        ),
      ),
    );
  }

  Set<String> describe(List<ElementData> elements) {
    return elements.map((e) => '${e.type}:${e.rect}').toSet();
  }

  testWidgets('getMaskElements with all widgets matches the two-walk union',
      (tester) async {
    await tester.pumpWidget(appWithContainerKey());

    final combined =
        PostHogMaskController.instance.getMaskElements(includeAllWidgets: true);
    final wrapperOnly =
        PostHogMaskController.instance.getPostHogWidgetWrapperElements();
    final allWidgets =
        PostHogMaskController.instance.getCurrentWidgetsElements();

    expect(combined, isNotNull);
    expect(
      describe(combined!),
      describe([...wrapperOnly!, ...allWidgets!]),
    );
    expect(combined, isNotEmpty);
  });

  testWidgets('getMaskElements without all widgets matches the wrapper walk',
      (tester) async {
    await tester.pumpWidget(appWithContainerKey());

    final combined = PostHogMaskController.instance
        .getMaskElements(includeAllWidgets: false);
    final wrapperOnly =
        PostHogMaskController.instance.getPostHogWidgetWrapperElements();

    expect(combined, isNotNull);
    expect(describe(combined!), describe(wrapperOnly!));
  });

  test('getMaskElements returns null without a mounted container', () {
    expect(
      PostHogMaskController.instance.getMaskElements(includeAllWidgets: true),
      isNull,
    );
  });
}
