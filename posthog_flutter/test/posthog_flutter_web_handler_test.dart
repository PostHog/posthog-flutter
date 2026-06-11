@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_flutter_web_handler.dart';

// Browser-only: handleWebMethodCall talks to the posthog-js instance on
// `window.posthog`, so these run under `flutter test --platform chrome`.
void main() {
  // The most recent options object passed to the fake posthog-js captureLog.
  JSObject? capturedOptions;

  setUp(() {
    capturedOptions = null;

    // Install a fake `window.posthog` whose captureLog records its argument.
    final fake = JSObject();
    fake.setProperty(
      'captureLog'.toJS,
      ((JSObject options) {
        capturedOptions = options;
      }).toJS,
    );
    globalContext.setProperty('posthog'.toJS, fake);
  });

  Map<Object?, Object?> readOptions() =>
      capturedOptions!.dartify()! as Map<Object?, Object?>;

  group('handleWebMethodCall captureLog', () {
    test('remaps trace fields to snake_case for posthog-js', () async {
      await handleWebMethodCall(const MethodCall('captureLog', {
        'body': 'checkout completed',
        'level': 'warn',
        'attributes': {'order_id': 'ord_789'},
        'traceId': '4bf92f3577b34da6a3ce929d0e0e4736',
        'spanId': '00f067aa0ba902b7',
        'traceFlags': 1,
      }));

      final options = readOptions();
      expect(options['body'], 'checkout completed');
      expect(options['level'], 'warn');
      expect(options['attributes'], {'order_id': 'ord_789'});
      // posthog-js expects snake_case, unlike the camelCase native channel.
      expect(options['trace_id'], '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(options['span_id'], '00f067aa0ba902b7');
      expect(options['trace_flags'], 1);
      expect(options.containsKey('traceId'), isFalse);
      expect(options.containsKey('spanId'), isFalse);
      expect(options.containsKey('traceFlags'), isFalse);
    });

    test('defaults a missing level to info', () async {
      await handleWebMethodCall(const MethodCall('captureLog', {
        'body': 'hello',
      }));

      expect(readOptions()['level'], 'info');
    });

    test('emits an explicit traceFlags of 0 but omits trace fields when null',
        () async {
      await handleWebMethodCall(const MethodCall('captureLog', {
        'body': 'x',
        'traceFlags': 0,
      }));

      final options = readOptions();
      // trace_flags 0 is meaningful (W3C sampled-false), so it must survive.
      expect(options['trace_flags'], 0);
      expect(options.containsKey('trace_id'), isFalse);
      expect(options.containsKey('span_id'), isFalse);
    });
  });
}
