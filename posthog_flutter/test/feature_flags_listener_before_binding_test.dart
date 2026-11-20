import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

// Its own file so the binding and the platform instance don't exist yet.
void main() {
  test('listener added before the binding receives native loads', () async {
    final received = <PostHogFeatureFlagsLoaded>[];
    final subscription = Posthog().onFeatureFlags(received.add);
    addTearDown(subscription.unsubscribe);

    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('posthog_flutter');
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      channel.codec
          .encodeMethodCall(const MethodCall('onFeatureFlagsCallback', {
        'generation': 0,
        'variants': {'early-flag': true},
        'errorsLoading': false,
      })),
      (_) {},
    );
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(received.map((loaded) => loaded.variants), [
      {'early-flag': true}
    ]);
  });
}
