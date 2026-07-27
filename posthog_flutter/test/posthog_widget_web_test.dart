@TestOn('browser')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

import 'posthog_flutter_platform_interface_fake.dart';

// Browser-only: these pin what PostHogWidget must *not* do on web, so they
// only mean anything under `flutter test --platform chrome`.
void main() {
  Future<void> setupPosthog() async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    final config = PostHogConfig('test_project_token');
    config.sessionReplay = true;
    await Posthog().setup(config);
  }

  Future<PostHogWidgetState> pumpReplayWidget(WidgetTester tester) async {
    await tester.pumpWidget(
      PostHogWidget(child: Container(color: const Color(0xFF00FF00))),
    );
    return tester.state<PostHogWidgetState>(find.byType(PostHogWidget));
  }

  tearDown(() async {
    await Posthog().close();
  });

  group('PostHogWidget on web', () {
    testWidgets('does not start the periodic capture', (tester) async {
      await setupPosthog();

      final state = await pumpReplayWidget(tester);

      expect(state.debugCaptureRunning, isFalse);
    });

    testWidgets('stays idle when session recording turns active',
        (tester) async {
      await setupPosthog();
      final state = await pumpReplayWidget(tester);

      PostHogInternalEvents.sessionRecordingActive.value = false;
      PostHogInternalEvents.sessionRecordingActive.value = true;
      await tester.pump();

      expect(state.debugCaptureRunning, isFalse);
    });

    testWidgets('still mounts the mask controller container', (tester) async {
      await setupPosthog();
      await pumpReplayWidget(tester);

      expect(PostHogMaskController.instance.containerKey.currentContext,
          isNotNull);
    });
  });
}
