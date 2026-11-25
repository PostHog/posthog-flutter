import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';
import 'package:posthog_flutter/src/posthog_widget.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterPlatformFake();
    await Posthog().close();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSessionReplayState') {
        return {'isActive': false, 'sessionId': null};
      }
      return null;
    });
  });

  tearDown(() async {
    await Posthog().close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<List<String?>> recordDebugPrint(Future<void> Function() action) async {
    final messages = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
    try {
      await action();
    } finally {
      debugPrint = originalDebugPrint;
    }
    return messages;
  }

  testWidgets('mounting before setup warns once on native and not on web',
      (tester) async {
    final messages = await recordDebugPrint(() async {
      await tester.pumpWidget(const PostHogWidget(child: SizedBox()));
      final state = tester.state(find.byType(PostHogWidget));
      await tester.pumpWidget(const PostHogWidget(child: SizedBox.expand()));
      expect(tester.state(find.byType(PostHogWidget)), same(state));
      await tester.pumpWidget(const SizedBox());
    });

    expect(
      messages,
      kIsWeb
          ? isEmpty
          : equals([
              '[PostHog] PostHogWidget mounted before Posthog().setup(). '
                  'If you intend to use mobile session replay, call setup() before runApp(), '
                  'or remount PostHogWidget after setup(). '
                  'Otherwise, you can ignore this message.',
            ]),
    );
  });

  for (final sessionReplay in [false, true]) {
    testWidgets('setup before mounting does not warn (replay: $sessionReplay)',
        (tester) async {
      await Posthog().setup(
          PostHogConfig('test_project_token')..sessionReplay = sessionReplay);

      final messages = await recordDebugPrint(() async {
        await tester.pumpWidget(const PostHogWidget(child: SizedBox()));
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1));
      });

      expect(messages, isEmpty);
    });
  }

  group('app lifecycle', () {
    Future<PostHogWidgetState> mountReplay(WidgetTester tester) async {
      await Posthog()
          .setup(PostHogConfig('test_project_token')..sessionReplay = true);
      await tester.pumpWidget(const PostHogWidget(child: SizedBox()));
      await tester.pump(const Duration(milliseconds: 1));
      return tester.state<PostHogWidgetState>(find.byType(PostHogWidget));
    }

    tearDown(() {
      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    Future<void> unmount(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    for (final background in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      testWidgets('change detector stops on $background and restarts on resume',
          (tester) async {
        final state = await mountReplay(tester);
        expect(state.debugChangeDetectorRunning, isTrue);

        tester.binding.handleAppLifecycleStateChanged(background);
        expect(state.debugChangeDetectorRunning, isFalse);

        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        expect(state.debugChangeDetectorRunning, isTrue);
        await unmount(tester);
      }, skip: kIsWeb);
    }

    testWidgets('mounting while backgrounded starts only on resume',
        (tester) async {
      // inactive still renders frames, so the widget can mount.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final state = await mountReplay(tester);
      expect(state.debugChangeDetectorRunning, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(state.debugChangeDetectorRunning, isTrue);
      await unmount(tester);
    }, skip: kIsWeb);

    testWidgets('recording enabled while paused starts sampling on resume',
        (tester) async {
      final state = await mountReplay(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      PostHogInternalEvents.sessionRecordingActive.value = false;
      PostHogInternalEvents.sessionRecordingActive.value = true;
      expect(state.debugChangeDetectorRunning, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(state.debugChangeDetectorRunning, isTrue);
      await unmount(tester);
    }, skip: kIsWeb);

    testWidgets('resume does not restart a detector stopped by the recording',
        (tester) async {
      final state = await mountReplay(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      PostHogInternalEvents.sessionRecordingActive.value = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(state.debugChangeDetectorRunning, isFalse);
      PostHogInternalEvents.sessionRecordingActive.value = true;
      expect(state.debugChangeDetectorRunning, isTrue);
      await unmount(tester);
    }, skip: kIsWeb);
  });
}
