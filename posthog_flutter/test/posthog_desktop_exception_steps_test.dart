import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_desktop_exception_steps.dart';

void main() {
  int bytesOf(Map<String, Object?> step) =>
      utf8.encode(jsonEncode(step)).length;

  List<Object?> messagesOf(ExceptionStepsBuffer buffer) =>
      [for (final step in buffer.steps) step[r'$message']];

  group('ExceptionStepsBuffer', () {
    test('records the message, the call time and the properties', () {
      final buffer = ExceptionStepsBuffer(maxBytes: 32768);
      final before = DateTime.now().toUtc();

      buffer.add('User tapped Checkout', properties: {'screen': 'cart'});

      final after = DateTime.now().toUtc();
      final step = buffer.steps.single;
      expect(step[r'$message'], 'User tapped Checkout');
      expect(step['screen'], 'cart');

      final timestamp = step[r'$timestamp']! as String;
      expect(
        timestamp,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')),
      );
      final recordedAt = DateTime.parse(timestamp);
      expect(
        recordedAt.millisecondsSinceEpoch,
        inInclusiveRange(
          before.millisecondsSinceEpoch,
          after.millisecondsSinceEpoch,
        ),
      );
    });

    test('ignores the reserved keys of the properties', () {
      final buffer = ExceptionStepsBuffer(maxBytes: 32768);

      buffer.add('step', properties: {
        r'$message': 'spoofed',
        r'$timestamp': 'spoofed',
        'kept': true,
      });

      final step = buffer.steps.single;
      expect(step[r'$message'], 'step');
      expect(step[r'$timestamp'], isNot('spoofed'));
      expect(step['kept'], isTrue);
    });

    test('normalizes values like event properties', () {
      final buffer = ExceptionStepsBuffer(maxBytes: 32768);
      final date = DateTime.utc(2026, 1, 2);

      buffer.add('step', properties: {
        'date': date,
        'nested': {'kept': 1, 'dropped': null},
      });

      final step = buffer.steps.single;
      expect(step['date'], date.toString());
      expect(step['nested'], {'kept': 1});
    });

    test('keeps a step with a number JSON cannot represent, as its string', () {
      final buffer = ExceptionStepsBuffer(maxBytes: 32768);

      buffer.add('step', properties: {
        'ratio': double.nan,
        'limits': [double.infinity, double.negativeInfinity],
      });

      final step = buffer.steps.single;
      expect(step['ratio'], 'NaN');
      expect(step['limits'], ['Infinity', '-Infinity']);
    });

    test('evicts the oldest steps to stay within the budget', () {
      final probe = ExceptionStepsBuffer(maxBytes: 32768)..add('step 1');
      final buffer = ExceptionStepsBuffer(
        maxBytes: bytesOf(probe.steps.single) * 2,
      );

      buffer
        ..add('step 1')
        ..add('step 2')
        ..add('step 3');

      expect(messagesOf(buffer), ['step 2', 'step 3']);
    });

    test('rejects a step larger than the budget and keeps the others', () {
      final buffer = ExceptionStepsBuffer(maxBytes: 200);

      buffer
        ..add('small')
        ..add('large', properties: {'payload': 'x' * 500});

      expect(messagesOf(buffer), ['small']);
    });

    test('measures the budget in UTF-8 bytes', () {
      final probe = ExceptionStepsBuffer(maxBytes: 32768)..add('a' * 10);
      // Same number of characters, 10 more bytes.
      final buffer = ExceptionStepsBuffer(
        maxBytes: bytesOf(probe.steps.single) + 5,
      );

      buffer.add('é' * 10);

      expect(buffer.steps, isEmpty);
    });

    test('ignores an empty message', () {
      final buffer = ExceptionStepsBuffer(maxBytes: 32768);

      buffer.add('');

      expect(buffer.steps, isEmpty);
    });
  });
}
