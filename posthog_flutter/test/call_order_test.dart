import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/utils/call_order.dart';

void main() {
  late CallOrder order;
  late List<String> calls;

  setUp(() {
    order = CallOrder();
    calls = [];
  });

  Future<void> record(String name) async => calls.add(name);

  test('runs a call immediately when nothing is in flight', () {
    order.run(() => record('reset'));
    order.event(() => 'checkout', record);

    expect(calls, ['reset', 'checkout']);
  });

  test('a call waits for an event whose hook is still running', () async {
    final hook = Completer<String>();
    final sent = order.event(() => hook.future, record);
    final reset = order.run(() => record('reset'));
    await pumpEventQueue();
    expect(calls, isEmpty);

    hook.complete('checkout');
    await Future.wait([sent, reset]);

    expect(calls, ['checkout', 'reset']);
  });

  test('events go out in call order whichever hook finishes first', () async {
    final slow = Completer<String>();
    final sent = [
      order.event(() => slow.future, record),
      order.event(() => Future.value('fast'), record),
      order.event(() => 'sync', record),
    ];
    await pumpEventQueue();
    slow.complete('slow');
    await Future.wait(sent);

    expect(calls, ['slow', 'fast', 'sync']);
  });

  test('a hook sees calls made before its event', () async {
    var user = 'old-user';
    final slow = Completer<String>();
    final sent = [
      order.event(() => slow.future, record),
      order.run(() async => user = 'new-user'),
      order.event(() => 'checkout as $user', record),
    ];
    await pumpEventQueue();
    slow.complete('slow');
    await Future.wait(sent);

    expect(calls, ['slow', 'checkout as new-user']);
  });

  test('a call made from the hook does not wait for its own event', () async {
    final sent = order.event(() async {
      await order.run(() => record('from_hook'));
      return 'checkout';
    }, record);
    final reset = order.run(() => record('reset'));
    await Future.wait([sent, reset]);

    expect(calls, ['from_hook', 'checkout', 'reset']);
  });

  test('a call waits for an event sent again from the send step', () async {
    final sent = order.event(
      () => Future.value('renamed'),
      (name) => order.event(
        () => Future<void>.delayed(Duration.zero).then((_) => name),
        record,
      ),
    );
    final reset = order.run(() => record('reset'));
    await Future.wait([sent, reset]);

    expect(calls, ['renamed', 'reset']);
  });

  test('a hook that throws still lets later calls through, in order', () async {
    final earlier = Completer<String>();
    final sentEarlier = order.event(() => earlier.future, record);
    final sent = order.event<String>(
      () => Future.error(StateError('boom')),
      record,
    );
    final reset = order.run(() => record('reset'));

    earlier.complete('checkout');
    await expectLater(sent, throwsStateError);
    await Future.wait([sentEarlier, reset]);
    expect(calls, ['checkout', 'reset']);
  });

  test('stops holding calls back after maxWait, and still sends', () {
    fakeAsync((async) {
      final hook = Completer<String>();
      order.event(() => hook.future, record);
      order.run(() => record('reset'));

      async.elapse(CallOrder.maxWait - const Duration(milliseconds: 1));
      expect(calls, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, ['reset']);

      hook.complete('checkout');
      async.flushMicrotasks();
      expect(calls, ['reset', 'checkout']);
    });
  });
}
