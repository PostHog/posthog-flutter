@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

import 'posthog_flutter_platform_interface_fake.dart';

/// Browser-only. Nothing on web observes the screenshot pipeline — its output
/// is discarded — so the work it schedules is the only evidence it ran. These
/// tests mount [PostHogWidget] and deliberately never unmount it: a capture in
/// flight leaves a pending timer, which fails the test. That is the assertion,
/// which is why two of them carry no `expect`.
void main() {
  Future<void> setupPosthog() async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    final config = PostHogConfig('test_project_token');
    config.sessionReplay = true;
    await Posthog().setup(config);
  }

  Future<void> pumpReplayWidget(WidgetTester tester) async {
    await tester.pumpWidget(
      PostHogWidget(child: Container(color: const Color(0xFF00FF00))),
    );
  }

  tearDown(() async {
    await Posthog().close();
  });

  group('PostHogWidget on web', () {
    testWidgets('leaves no capture work pending after mounting',
        (tester) async {
      await setupPosthog();

      await pumpReplayWidget(tester);
    });

    testWidgets('stays idle when session recording turns active',
        (tester) async {
      await setupPosthog();
      await pumpReplayWidget(tester);

      PostHogInternalEvents.sessionRecordingActive.value = false;
      PostHogInternalEvents.sessionRecordingActive.value = true;
      await tester.pump();
    });

    testWidgets('still mounts the mask controller container', (tester) async {
      await setupPosthog();
      await pumpReplayWidget(tester);

      expect(PostHogMaskController.instance.containerKey.currentContext,
          isNotNull);
    });
  });
}
