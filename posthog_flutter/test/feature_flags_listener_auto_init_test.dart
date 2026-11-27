import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

// Its own file so no earlier test has created the platform instance, as in an
// app where native auto-init ran and onFeatureFlags is the first Dart call.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onFeatureFlags as the first SDK call receives native loads', () async {
    const channel = MethodChannel('posthog_flutter');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final received = <PostHogFeatureFlagsLoaded>[];
    final subscription = Posthog().onFeatureFlags(received.add);
    addTearDown(subscription.unsubscribe);

    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      channel.codec
          .encodeMethodCall(const MethodCall('onFeatureFlagsCallback', {
        'generation': 0,
        'variants': {'auto-init-flag': true},
        'errorsLoading': false,
      })),
      (_) {},
    );
    await pumpEventQueue();

    expect(received.map((loaded) => loaded.variants), [
      {'auto-init-flag': true}
    ]);
  });
}
