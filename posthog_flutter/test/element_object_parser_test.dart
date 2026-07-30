import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  Future<void> setupPosthog({
    required bool maskAllTexts,
    required bool maskAllImages,
  }) async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    final config = PostHogConfig('test_project_token');
    config.sessionReplayConfig.maskAllTexts = maskAllTexts;
    config.sessionReplayConfig.maskAllImages = maskAllImages;
    await Posthog().setup(config);
    // the controller singleton may have been created before this setup
    PostHogMaskController.instance.refreshParsers(config.sessionReplayConfig);
  }

  tearDown(() async {
    PostHogMaskController.instance.refreshParsers(null);
    await Posthog().close();
  });

  Future<void> pumpTree(WidgetTester tester) async {
    // real async work: it never completes inside the test's FakeAsync zone
    final ui.Image image = (await tester.runAsync(
      () => createTestImage(width: 20, height: 20),
    ))!;
    addTearDown(image.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: PostHogMaskController.instance.containerKey,
          child: Scaffold(
            body: Column(
              children: [
                const Text('some text'),
                RawImage(image: image, width: 20, height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Set<String> types(List<ElementData> elements) =>
      elements.map((e) => e.type).toSet();

  testWidgets(
      'maskAllTexts=false keeps Text out of the mask set even when '
      'maskAllImages is on', (tester) async {
    await setupPosthog(maskAllTexts: false, maskAllImages: true);
    await pumpTree(tester);

    final elements =
        PostHogMaskController.instance.getMaskElements(includeAllWidgets: true);

    expect(elements, isNotNull);
    expect(types(elements!), isNot(contains('Text')));
    expect(types(elements), isNot(contains('RichText')));
    expect(types(elements), contains('RawImage'));
  });

  testWidgets('maskAllTexts=true still masks Text', (tester) async {
    await setupPosthog(maskAllTexts: true, maskAllImages: true);
    await pumpTree(tester);

    final elements =
        PostHogMaskController.instance.getMaskElements(includeAllWidgets: true);

    expect(elements, isNotNull);
    expect(types(elements!), contains('Text'));
  });
}
