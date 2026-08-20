import 'package:flutter_test/flutter_test.dart';

/// Interleaves fake-async work (channel round trips, the detector's timer) with
/// real async (rasterization), since neither pumping nor [WidgetTester.runAsync]
/// alone drives a capture to completion.
///
/// [settleUntil] is the one to use when asserting that something *did* happen:
/// it returns as soon as [done] is satisfied, so a slow machine costs latency
/// rather than a failure. [settleCapture] drains a fixed budget instead, which
/// is what negative assertions need — they have to be sure the pipeline was
/// given every chance before concluding nothing was sent.
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
/// Only for negative assertions (`isNot(contains(...))`), where an early exit
/// would make the assertion pass for the wrong reason — the capture simply not
/// having finished. Raise the budget if a capture gains awaits.
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
