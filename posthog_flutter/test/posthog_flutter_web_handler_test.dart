@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter_web.dart';
import 'package:posthog_flutter/src/feature_flag_result.dart';
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

  group('handleWebMethodCall reloadFeatureFlags', () {
    late JSFunction? listener;
    late int reloads;
    late int unsubscribes;

    /// Installs a fake posthog-js whose reload answers with [answer], if any.
    void installFake({
      Map<String, Object?> config = const {},
      ({Map<String, Object> variants, bool errorsLoading})? answer,
      String? asyncStatus,
    }) {
      listener = null;
      reloads = 0;
      unsubscribes = 0;
      var current = {'cached': true}.jsify()!;
      final featureFlags = JSObject()
        ..setProperty('getFlagVariants'.toJS, (() => current).toJS);
      if (asyncStatus != null) {
        featureFlags.setProperty(
          'reloadFeatureFlagsAsync'.toJS,
          (() => Future(() {
                current = {'fresh': 'v2'}.jsify()!;
                return {'status': asyncStatus}.jsify();
              }).toJS).toJS,
        );
      }
      final fake = JSObject()
        ..setProperty('featureFlags'.toJS, featureFlags)
        ..setProperty('config'.toJS, config.jsify())
        ..setProperty(
          'onFeatureFlags'.toJS,
          ((JSFunction callback) {
            listener = callback;
            callback.callAsFunction(null, <String>[].jsify(), current);
            return (() => unsubscribes++).toJS;
          }).toJS,
        )
        ..setProperty(
          'reloadFeatureFlags'.toJS,
          (() {
            reloads++;
            if (answer == null) return;
            Future(() => listener?.callAsFunction(
                  null,
                  answer.variants.keys.toList().jsify(),
                  answer.variants.jsify(),
                  {'errorsLoading': answer.errorsLoading}.jsify(),
                ));
          }).toJS,
        );
      globalContext.setProperty('posthog'.toJS, fake);
    }

    test('completes with the flags the reload delivers, not the replayed ones',
        () async {
      installFake(answer: (variants: {'fresh': 'v2'}, errorsLoading: true));

      final result =
          await handleWebMethodCall(const MethodCall('reloadFeatureFlags'))
              as Map<String, Object?>;

      expect(result, {
        'variants': {'fresh': 'v2'},
        'errorsLoading': true,
      });
      expect(unsubscribes, 1);
    });

    test('awaits reloadFeatureFlagsAsync when posthog-js has it', () async {
      installFake(asyncStatus: 'loaded');

      final result =
          await handleWebMethodCall(const MethodCall('reloadFeatureFlags'))
              as Map<String, Object?>;

      expect(result, {
        'variants': {'fresh': 'v2'},
        'errorsLoading': false,
      });
      expect(reloads, 0);
    });

    test('reports an error when reloadFeatureFlagsAsync skips the request',
        () async {
      installFake(asyncStatus: 'skipped');

      final result =
          await handleWebMethodCall(const MethodCall('reloadFeatureFlags'))
              as Map<String, Object?>;

      expect(result['errorsLoading'], isTrue);
    });

    test('completes right away with an error when flags are disabled',
        () async {
      installFake(config: {'advanced_disable_feature_flags': true});

      final result =
          await handleWebMethodCall(const MethodCall('reloadFeatureFlags'))
              as Map<String, Object?>;

      expect(result, {
        'variants': {'cached': true},
        'errorsLoading': true,
      });
      expect(reloads, 0);
    });

    test('completes with an error when posthog-js never calls back', () async {
      installFake(config: {'feature_flag_request_timeout_ms': 5});

      final result =
          await handleWebMethodCall(const MethodCall('reloadFeatureFlags'))
              as Map<String, Object?>;

      expect(result, {
        'variants': {'cached': true},
        'errorsLoading': true,
      });
      expect(reloads, 1);
      expect(unsubscribes, 1);
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

  test('PosthogFlutterWeb captureFeatureView captures the native event shape',
      () async {
    final calls = <List<Object?>>[];
    final fake = JSObject();
    fake.setProperty(
      'getFeatureFlagResult'.toJS,
      ((JSString key, JSAny? options) {
        calls.add(['getFeatureFlagResult', key.toDart, options.dartify()]);
        return {'key': key.toDart, 'enabled': true, 'variant': 'control'}
            .jsify();
      }).toJS,
    );
    fake.setProperty(
      'capture'.toJS,
      ((JSString event, JSAny? properties, JSAny? options) {
        final props = properties.dartify()! as Map;
        calls.add([
          'capture',
          event.toDart,
          props['feature_flag'],
          props['feature_flag_variant'],
          options.dartify(),
        ]);
      }).toJS,
    );
    globalContext.setProperty('posthog'.toJS, fake);

    await PosthogFlutterWeb().captureFeatureView(flag: 'checkout');

    expect(calls, [
      [
        'getFeatureFlagResult',
        'checkout',
        {'send_event': false}
      ],
      [
        'capture',
        r'$feature_view',
        'checkout',
        'control',
        {
          r'$set': {r'$feature_view/checkout': 'control'}
        },
      ],
    ]);
  });

  test('PosthogFlutterWeb feature events carry the current screen until close',
      () async {
    final screenNames = <String, Object?>{};
    final fake = JSObject();
    fake.setProperty(
      'capture'.toJS,
      ((JSString event, JSAny? properties, JSAny? options) {
        final props = properties.dartify()! as Map;
        screenNames[event.toDart] = props[r'$screen_name'];
      }).toJS,
    );
    globalContext.setProperty('posthog'.toJS, fake);
    final web = PosthogFlutterWeb();

    await web.screen(screenName: 'Cart');
    await web.captureFeatureInteraction(flag: 'checkout', flagVariant: 'a');
    expect(screenNames[r'$feature_interaction'], 'Cart');

    await web.close();
    await web.captureFeatureView(flag: 'checkout', flagVariant: 'a');
    expect(screenNames[r'$feature_view'], isNull);
  });

  group('PosthogFlutterWeb sendFeatureFlagEvent', () {
    late Map<String, Object?> optionsByMethod;

    setUp(() {
      optionsByMethod = {};
      final fake = JSObject();
      for (final method in ['getFeatureFlag', 'isFeatureEnabled']) {
        fake.setProperty(
          method.toJS,
          ((JSString key, JSAny? options) {
            optionsByMethod[method] = options.dartify();
            return true.toJS;
          }).toJS,
        );
      }
      globalContext.setProperty('posthog'.toJS, fake);
    });

    for (final (sendFeatureFlagEvent, expected) in [
      (null, <String, Object?>{}),
      (false, {'send_event': false}),
      (true, {'send_event': true}),
    ]) {
      test('maps $sendFeatureFlagEvent to posthog-js options $expected',
          () async {
        final web = PosthogFlutterWeb();
        await web.getFeatureFlag(
            key: 'flag', sendFeatureFlagEvent: sendFeatureFlagEvent);
        await web.isFeatureEnabled('flag',
            sendFeatureFlagEvent: sendFeatureFlagEvent);

        expect(optionsByMethod, {
          'getFeatureFlag': expected,
          'isFeatureEnabled': expected,
        });
      });
    }
  });

  group('PosthogFlutterWeb getAllFeatureFlags', () {
    test('decodes the posthog-js results', () async {
      final fake = JSObject();
      fake.setProperty(
        'getAllFeatureFlags'.toJS,
        (() => [
              {'key': 'on', 'enabled': true},
              {'key': 'multi', 'enabled': true, 'variant': 'control'},
            ].jsify()).toJS,
      );
      globalContext.setProperty('posthog'.toJS, fake);

      expect(await PosthogFlutterWeb().getAllFeatureFlags(), [
        const PostHogFeatureFlagResult(key: 'on', enabled: true),
        const PostHogFeatureFlagResult(
            key: 'multi', enabled: true, variant: 'control'),
      ]);
    });

    test('returns null when posthog-js predates getAllFeatureFlags', () async {
      globalContext.setProperty('posthog'.toJS, JSObject());

      expect(await PosthogFlutterWeb().getAllFeatureFlags(), isNull);
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
