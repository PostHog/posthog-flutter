@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/posthog_flutter_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final captures = <Map<String, Object?>>[];

  setUp(() {
    captures.clear();
    final fake = JSObject();
    fake.setProperty(
      'capture'.toJS,
      ((JSString event, JSAny? properties, [JSAny? options]) {
        captures.add({
          'event': event.toDart,
          'properties': properties?.dartify(),
        });
      }).toJS,
    );
    fake.setProperty(
      'captureException'.toJS,
      ((JSAny? error, JSAny? properties) {
        captures.add({
          'event': r'$exception',
          'properties': properties?.dartify(),
        });
      }).toJS,
    );
    globalContext.setProperty('posthog'.toJS, fake);
  });

  test('feature events carry the screen name beforeSend accepted', () async {
    final web = PosthogFlutterWeb();
    await web.setup(PostHogConfig('test_token', beforeSend: [
      (event) {
        final name = event.properties?[r'$screen_name'];
        if (name == 'Secret') return null;
        if (name == 'Cart') event.properties?[r'$screen_name'] = 'Basket';
        return event;
      },
    ]));

    await web.screen(screenName: 'Cart');
    await web.screen(screenName: 'Secret');
    await web.captureFeatureView(flag: 'checkout', flagVariant: 'a');

    expect((captures.last['properties'] as Map)[r'$screen_name'], 'Basket');
  });

  group('calls made while an event is in flight', () {
    late List<String> calls;

    setUp(() {
      calls = [];
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      fake.setProperty(
        'capture'.toJS,
        ((JSString event, [JSAny? a, JSAny? b]) => calls.add(event.toDart))
            .toJS,
      );
      for (final method in [
        'captureException',
        'reset',
        'identify',
        'alias',
        'register',
        'unregister',
        'group',
        'opt_in_capturing',
        'opt_out_capturing',
      ]) {
        fake.setProperty(
          method.toJS,
          (([JSAny? a, JSAny? b, JSAny? c, JSAny? d]) => calls.add(method))
              .toJS,
        );
      }
    });

    Future<PosthogFlutterWeb> setUpWeb({bool slowBeforeSend = true}) async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        if (slowBeforeSend)
          (event) async {
            await Future<void>.delayed(Duration.zero);
            return event;
          },
      ]));
      return web;
    }

    List<Future<void>> captureAll(PosthogFlutterWeb web) => [
          web.capture(eventName: 'checkout'),
          web.screen(screenName: 'Cart'),
          web.captureException(error: StateError('boom')),
        ];

    const captured = ['checkout', r'$screen', 'captureException'];

    test('reach posthog-js first without beforeSend', () async {
      final web = await setUpWeb(slowBeforeSend: false);

      final sent = captureAll(web);
      await web.reset();
      await Future.wait(sent);

      expect(calls, [...captured, 'reset']);
    });

    final followUps = <String, Future<void> Function(PosthogFlutterWeb)>{
      'reset': (web) => web.reset(),
      'identify': (web) => web.identify(userId: 'new-user'),
      'alias': (web) => web.alias(alias: 'new-alias'),
      'register': (web) => web.register('plan', 'pro'),
      'unregister': (web) => web.unregister('plan'),
      'group': (web) => web.group(groupType: 'company', groupKey: 'acme'),
      'opt_in_capturing': (web) => web.enable(),
      'opt_out_capturing': (web) => web.disable(),
    };
    for (final MapEntry(key: method, value: call) in followUps.entries) {
      test('$method waits for events whose beforeSend is still running',
          () async {
        final web = await setUpWeb();

        final sent = captureAll(web);
        await call(web);
        await Future.wait(sent);

        expect(calls, [...captured, method]);
      });
    }

    test('an account switch does not reach an earlier event', () async {
      final web = await setUpWeb();

      final sent = web.capture(eventName: 'checkout');
      await web.reset();
      await web.identify(userId: 'new-user');
      await web.register('account_email', 'new@example.invalid');
      await web.group(groupType: 'company', groupKey: 'new-company');
      await sent;

      expect(calls, ['checkout', 'reset', 'identify', 'register', 'group']);
    });

    test('a feature event waits for an earlier event', () async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          if (event.event == 'checkout') {
            await Future<void>.delayed(Duration.zero);
          }
          return event;
        },
      ]));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.captureFeatureView(flag: 'flag', flagVariant: 'a'),
      ];
      await web.reset();
      await Future.wait(sent);

      expect(calls, ['checkout', r'$feature_view', 'reset']);
    });

    for (final slow in [false, true]) {
      test(
          'a feature event looks its flag up after earlier calls '
          '(${slow ? 'async' : 'no'} beforeSend)', () async {
        final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
        var variant = 'old-user-variant';
        fake.setProperty(
          'reset'.toJS,
          (() {
            calls.add('reset');
            variant = 'new-user-variant';
          }).toJS,
        );
        fake.setProperty(
          'getFeatureFlagResult'.toJS,
          ((JSString key, [JSAny? options]) {
            calls.add('lookup $variant');
            return {'key': key.toDart, 'enabled': true, 'variant': variant}
                .jsify();
          }).toJS,
        );
        final web = await setUpWeb(slowBeforeSend: slow);

        final sent = [
          if (slow) web.capture(eventName: 'checkout'),
          web.captureFeatureView(flag: 'flag'),
        ];
        await web.reset();
        await Future.wait(sent);

        expect(calls, [
          if (slow) 'checkout',
          'lookup old-user-variant',
          r'$feature_view',
          'reset',
        ]);
      });
    }

    test('beforeSend can capture without waiting for itself', () async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          if (event.event == 'checkout') {
            await web.capture(eventName: 'from_hook');
          }
          return event;
        },
      ]));

      final sent = web.capture(eventName: 'checkout');
      await web.reset();
      await sent;

      expect(calls, ['from_hook', 'checkout', 'reset']);
    });
  });

  test('beforeSend null drops capture on web', () async {
    final web = PosthogFlutterWeb();
    await web.setup(
      PostHogConfig('test_token', beforeSend: [(event) => null]),
    );

    await web.capture(
      eventName: 'secret',
      properties: {'email': 'a@b.c'},
    );

    expect(captures, isEmpty);
  });

  test('beforeSend can strip a property before web capture', () async {
    final web = PosthogFlutterWeb();
    await web.setup(
      PostHogConfig('test_token', beforeSend: [
        (event) {
          event.properties?.remove('email');
          return event;
        },
      ]),
    );

    await web.capture(
      eventName: 'checkout',
      properties: {'email': 'a@b.c', 'plan': 'pro'},
    );

    expect(captures, hasLength(1));
    expect(captures.single['event'], 'checkout');
    final properties = captures.single['properties'] as Map;
    expect(properties.containsKey('email'), isFalse);
    expect(properties['plan'], 'pro');
  });

  test('beforeSend null drops screen and captureException on web', () async {
    final web = PosthogFlutterWeb();
    await web.setup(
      PostHogConfig('test_token', beforeSend: [(event) => null]),
    );

    await web.screen(screenName: 'Checkout');
    await web.captureException(error: StateError('boom'));

    expect(captures, isEmpty);
  });
}
