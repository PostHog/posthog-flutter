import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

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
                  'Mobile session replay will not start for this widget instance. '
                  'Call setup() before runApp(), or remount PostHogWidget after setup().',
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
}
