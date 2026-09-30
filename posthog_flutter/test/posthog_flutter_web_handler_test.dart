@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter_web.dart';
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

  group('handleWebMethodCall addExceptionStep', () {
    String? capturedMessage;
    JSAny? capturedProperties;
    var captured = false;

    setUp(() {
      capturedMessage = null;
      capturedProperties = null;
      captured = false;

      final fake = JSObject();
      fake.setProperty(
        'addExceptionStep'.toJS,
        ((JSString message, JSAny? properties) {
          captured = true;
          capturedMessage = message.toDart;
          capturedProperties = properties;
        }).toJS,
      );
      globalContext.setProperty('posthog'.toJS, fake);
    });

    test('forwards message and properties to posthog-js', () async {
      await handleWebMethodCall(const MethodCall('addExceptionStep', {
        'message': 'User tapped Checkout',
        'properties': {'screen': 'cart'},
      }));

      expect(capturedMessage, 'User tapped Checkout');
      expect(capturedProperties.dartify(), {'screen': 'cart'});
    });

    test('forwards null properties when none provided', () async {
      await handleWebMethodCall(const MethodCall('addExceptionStep', {
        'message': 'Opened modal',
      }));

      expect(captured, isTrue);
      expect(capturedMessage, 'Opened modal');
      expect(capturedProperties, isNull);
    });
  });

  // Guards the web wiring: PosthogFlutterWeb must override addExceptionStep so
  // the call actually reaches posthog-js. Without the override it falls through
  // to the platform interface and throws UnimplementedError on web.
  group('PosthogFlutterWeb addExceptionStep', () {
    String? capturedMessage;
    JSAny? capturedProperties;

    setUp(() {
      capturedMessage = null;
      capturedProperties = null;

      final fake = JSObject();
      fake.setProperty(
        'addExceptionStep'.toJS,
        ((JSString message, JSAny? properties) {
          capturedMessage = message.toDart;
          capturedProperties = properties;
        }).toJS,
      );
      globalContext.setProperty('posthog'.toJS, fake);
    });

    test('override forwards message and normalized properties to posthog-js',
        () async {
      await PosthogFlutterWeb().addExceptionStep(
        'User tapped Checkout',
        properties: {
          'screen': 'cart',
          'count': 3,
          'at': DateTime.utc(2026, 1, 2)
        },
      );

      expect(capturedMessage, 'User tapped Checkout');
      expect(capturedProperties.dartify(), {
        'screen': 'cart',
        'count': 3,
        'at': '2026-01-02 00:00:00.000Z',
      });
    });
  });

  group('PosthogFlutterWeb captureException', () {
    test('handles native JavaScript failures from posthog-js', () async {
      final failWithJavaScriptError = globalContext.callMethod<JSFunction>(
        'eval'.toJS,
        '() => { throw new Error("capture failed"); }'.toJS,
      );

      final fake = JSObject();
      fake.setProperty('captureException'.toJS, failWithJavaScriptError);
      fake.setProperty('capture'.toJS, failWithJavaScriptError);
      globalContext.setProperty('posthog'.toJS, fake);

      await expectLater(
        PosthogFlutterWeb().captureException(error: StateError('boom')),
        completes,
      );
    });
  });

  // captureException must route through posthog-js's captureException (not the
  // generic capture) so it attaches required metadata and any buffered
  // $exception_steps. The Dart-built payload is passed as additionalProperties,
  // which posthog-js spreads last — so our $exception_list must survive.
  group('handleWebMethodCall captureException', () {
    String? capturedMessage;
    JSAny? capturedProperties;
    var captured = false;

    setUp(() {
      capturedMessage = null;
      capturedProperties = null;
      captured = false;

      final fake = JSObject();
      fake.setProperty(
        'captureException'.toJS,
        ((JSString message, JSAny? properties) {
          captured = true;
          capturedMessage = message.toDart;
          capturedProperties = properties;
        }).toJS,
      );
      globalContext.setProperty('posthog'.toJS, fake);
    });

    test('forwards to captureException, preserving the Dart \$exception_list',
        () async {
      await handleWebMethodCall(const MethodCall('captureException', {
        'properties': {
          r'$exception_level': 'error',
          r'$exception_list': [
            {'type': 'StateError', 'value': 'boom'},
          ],
        },
      }));

      expect(captured, isTrue);
      // The trigger message is the exception value; its parse is discarded.
      expect(capturedMessage, 'boom');

      final props = capturedProperties!.dartify()! as Map<Object?, Object?>;
      // Our Dart-built payload wins over posthog-js's synthetic parse.
      expect(props[r'$exception_level'], 'error');
      final list = props[r'$exception_list'] as List;
      final first = list.first as Map;
      expect(first['type'], 'StateError');
      expect(first['value'], 'boom');
    });

    test('uses a fallback trigger message when no exception value is present',
        () async {
      await handleWebMethodCall(const MethodCall('captureException', {
        'properties': {r'$exception_level': 'error'},
      }));

      expect(captured, isTrue);
      expect(capturedMessage, 'Exception');
    });
  });

  group('appVersionProperties', () {
    test('maps the build name and number to the native property names', () {
      expect(
        appVersionProperties(buildName: '3.24.2', buildNumber: '183'),
        {r'$app_version': '3.24.2', r'$app_build': '183'},
      );
    });

    test('omits properties whose define is empty (Flutter < 3.47)', () {
      expect(appVersionProperties(buildName: '', buildNumber: ''), isEmpty);
      expect(
        appVersionProperties(buildName: '1.0.0', buildNumber: ''),
        {r'$app_version': '1.0.0'},
      );
    });
  });

  // capture and screen must carry the running build's version, like the
  // native SDKs do, without overriding a value the caller set explicitly.
  group('handleWebMethodCall app version', () {
    final captured = <String, Map<Object?, Object?>>{};

    setUp(() {
      captured.clear();

      final fake = JSObject();
      fake.setProperty(
        'capture'.toJS,
        ((JSString event, JSAny? properties, JSAny? options) {
          captured[event.toDart] =
              properties!.dartify()! as Map<Object?, Object?>;
        }).toJS,
      );
      globalContext.setProperty('posthog'.toJS, fake);
    });

    Matcher containsAppVersion() {
      const name = String.fromEnvironment('FLUTTER_BUILD_NAME');
      const number = String.fromEnvironment('FLUTTER_BUILD_NUMBER');
      expect(name, isNotEmpty,
          reason: 'Flutter must inject the package version');
      return allOf(
          containsPair(r'$app_version', name),
          number.isEmpty
              ? isNot(contains(r'$app_build'))
              : containsPair(r'$app_build', number));
    }

    test('capture attaches the compile-time app version', () async {
      await handleWebMethodCall(const MethodCall('capture', {
        'eventName': 'checkout',
        'properties': {'step': 1},
      }));

      expect(captured['checkout'], containsPair('step', 1));
      expect(captured['checkout'], containsAppVersion());
    });

    test('screen attaches the compile-time app version', () async {
      await handleWebMethodCall(const MethodCall('screen', {
        'screenName': 'Home',
      }));

      expect(captured[r'$screen'], containsAppVersion());
    });

    test('captureException attaches the compile-time app version', () async {
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      fake.setProperty(
          'captureException'.toJS,
          ((JSString message, JSAny? properties) {
            captured['exception'] =
                properties!.dartify()! as Map<Object?, Object?>;
          }).toJS);
      await handleWebMethodCall(const MethodCall('captureException', {
        'properties': {r'$exception_level': 'error'},
      }));
      expect(captured['exception'], containsAppVersion());
    });

    test('keeps an app version the caller set explicitly', () async {
      await handleWebMethodCall(const MethodCall('capture', {
        'eventName': 'checkout',
        'properties': {
          r'$app_version': 'custom',
          r'$app_build': 'custom-build'
        },
      }));

      expect(captured['checkout']![r'$app_version'], 'custom');
      expect(captured['checkout']![r'$app_build'], 'custom-build');
    });
  });
}
