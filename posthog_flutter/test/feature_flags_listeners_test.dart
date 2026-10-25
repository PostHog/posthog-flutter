import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/feature_flags_listeners.dart';
import 'package:posthog_flutter/src/feature_flags_loaded.dart';

PostHogFeatureFlagsLoaded loaded(String variant) => PostHogFeatureFlagsLoaded(
    variants: {'flag': variant}, errorsLoading: false);

void main() {
  final listeners = FeatureFlagsListeners.instance;
  final subscriptions = <PostHogFeatureFlagsSubscription>[];

  PostHogFeatureFlagsSubscription listen(
      List<PostHogFeatureFlagsLoaded> received) {
    final subscription = listeners.add(received.add);
    subscriptions.add(subscription);
    return subscription;
  }

  tearDown(() {
    for (final subscription in subscriptions) {
      subscription.unsubscribe();
    }
    subscriptions.clear();
    listeners.clear();
  });

  test('delivers each load until unsubscribed', () {
    final received = <PostHogFeatureFlagsLoaded>[];
    final subscription = listen(received);
    final first = loaded('a');

    listeners.deliver(first);
    subscription.unsubscribe();
    listeners.deliver(loaded('b'));

    expect(received, [first]);
  });

  test('replays the last load to a new listener once', () async {
    final last = loaded('a');
    listeners.deliver(last);
    final received = <PostHogFeatureFlagsLoaded>[];
    listen(received);

    await pumpEventQueue();

    expect(received, [last]);
  });

  test('skips the replay when a newer load arrives first', () async {
    listeners.deliver(loaded('a'));
    final received = <PostHogFeatureFlagsLoaded>[];
    listen(received);
    final newer = loaded('b');
    listeners.deliver(newer);

    await pumpEventQueue();

    expect(received, [newer]);
  });

  test('does not replay after clear', () async {
    listeners.deliver(loaded('a'));
    listeners.clear();
    final received = <PostHogFeatureFlagsLoaded>[];
    listen(received);

    await pumpEventQueue();

    expect(received, isEmpty);
  });

  test('skips a listener unsubscribed by an earlier one during delivery', () {
    late PostHogFeatureFlagsSubscription second;
    subscriptions.add(listeners.add((_) => second.unsubscribe()));
    final received = <PostHogFeatureFlagsLoaded>[];
    second = listen(received);

    listeners.deliver(loaded('a'));

    expect(received, isEmpty);
  });
}
