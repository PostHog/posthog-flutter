import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

// Its own file so the binding and the platform instance don't exist yet.
void main() {
  test('calls before the binding fall back, then setup reaches native',
      () async {
    final posthog = Posthog();
    final config = PostHogConfig('test-token', beforeSend: [(event) => event]);

    await posthog.setup(config);
    await posthog.capture(eventName: 'early');
    await posthog.screen(screenName: 'early');
    expect(await posthog.captureAi(eventName: r'$ai_generation'), isNull);
    await posthog.identify(userId: 'early');
    await posthog.captureException(error: StateError('early'));
    expect(await posthog.isFeatureEnabled('flag'), isFalse);
    expect(await posthog.getFeatureFlag('flag'), isNull);

    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('posthog_flutter');
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });

    await posthog.setup(config);

    expect(methods, ['setup']);
  });
}
