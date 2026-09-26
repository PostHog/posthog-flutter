@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';

import 'posthog_flutter_platform_interface_fake.dart';

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
    testWidgets('does not start screenshot polling after mounting',
        (tester) async {
      await setupPosthog();
      final timers = <Duration>[];
      await runZoned(() => pumpReplayWidget(tester),
          zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          timers.add(duration);
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ));
      expect(timers, isEmpty);
    });

    testWidgets('stays idle when session recording turns active',
        (tester) async {
      await setupPosthog();
      await pumpReplayWidget(tester);

      final timers = <Duration>[];
      runZoned(() {
        PostHogInternalEvents.sessionRecordingActive.value = false;
        PostHogInternalEvents.sessionRecordingActive.value = true;
      }, zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          timers.add(duration);
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ));
      expect(timers, isEmpty);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('still mounts the mask controller container', (tester) async {
      await setupPosthog();
      await pumpReplayWidget(tester);

      expect(PostHogMaskController.instance.containerKey.currentContext,
          isNotNull);
    });
  });
}
