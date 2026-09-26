import 'package:flutter_test/flutter_test.dart';

/// Interleaves fake-async work (channel round trips, the detector's timer) with
/// real async (rasterization), since neither pumping nor [WidgetTester.runAsync]
/// alone drives a capture to completion.
///
/// [settleUntil] is the one to use when asserting that something *did* happen:
/// it returns as soon as [done] is satisfied, so a slow machine costs latency
/// rather than a failure. Callers must still assert the milestone afterwards.
/// [settleCapture] advances a fixed budget, not a completion barrier.
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 80,
}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
}

/// Drains the capture pipeline for a fixed budget.
///
/// A negative assertion after this wait alone does not establish that an
/// asynchronous capture completed. Prefer an explicit completion signal.
Future<void> settleCapture(WidgetTester tester, {int rounds = 16}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
}

/// Advances one poll tick before settling. Boundaries leave the new session's
/// first frame to the forced-tick budget, so it cannot land in the same turn.
Future<void> settleCaptureAcrossTick(
  WidgetTester tester, {
  Duration interval = const Duration(seconds: 1),
}) async {
  await tester.pump(interval);
  await settleCapture(tester);
}
