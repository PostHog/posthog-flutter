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

  group('a reset() right after an un-awaited capture', () {
    late List<String> sentAs;
    late String distinctId;

    setUp(() {
      sentAs = [];
      distinctId = 'old-user';
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      fake.setProperty('get_distinct_id'.toJS, (() => distinctId.toJS).toJS);
      fake.setProperty('reset'.toJS, (() => distinctId = 'new-user').toJS);
      for (final method in ['capture', 'captureException']) {
        fake.setProperty(
          method.toJS,
          ((JSAny? a, JSAny? b, [JSAny? c]) {
            final props = b.dartify() as Map?;
            sentAs.add(props?['distinct_id'] as String? ?? distinctId);
          }).toJS,
        );
      }
    });

    test('sends the events as the old user without beforeSend', () async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token'));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.screen(screenName: 'Cart'),
        web.captureException(error: StateError('boom')),
      ];
      await web.reset();
      await Future.wait(sent);

      expect(sentAs, ['old-user', 'old-user', 'old-user']);
    });

    test('keeps an event when posthog-js loads during beforeSend', () async {
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      // The loader snippet's stub returns undefined until posthog-js loads.
      fake.setProperty('get_distinct_id'.toJS, (() => null).toJS);
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          fake.setProperty(
              'get_distinct_id'.toJS, (() => distinctId.toJS).toJS);
          return event;
        },
      ]));

      await web.capture(eventName: 'app_started');

      expect(sentAs, ['old-user']);
    });

    test('keeps the old user when beforeSend outlasts the reset', () async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          await Future<void>.delayed(Duration.zero);
          return event;
        },
      ]));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.screen(screenName: 'Cart'),
        web.captureException(error: StateError('boom')),
      ];
      await web.reset();
      await Future.wait(sent);

      expect(sentAs, ['old-user', 'old-user', 'old-user']);
    });

    test('does not pin the cookieless sentinel across an opt-in', () async {
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      distinctId = r'$posthog_cookieless';
      fake.setProperty(
          'opt_in_capturing'.toJS, (() => distinctId = 'new-user').toJS);
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          await Future<void>.delayed(Duration.zero);
          return event;
        },
      ]));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.screen(screenName: 'Cart'),
        web.captureException(error: StateError('boom')),
      ];
      await web.enable();
      await Future.wait(sent);

      expect(sentAs, ['new-user', 'new-user', 'new-user']);
    });

    test('does not pin the old user across a cookieless opt-out', () async {
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      fake.setProperty('opt_out_capturing'.toJS,
          (() => distinctId = r'$posthog_cookieless').toJS);
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          await Future<void>.delayed(Duration.zero);
          return event;
        },
      ]));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.screen(screenName: 'Cart'),
        web.captureException(error: StateError('boom')),
      ];
      await web.disable();
      await Future.wait(sent);

      expect(sentAs, List.filled(3, r'$posthog_cookieless'));
    });

    test('does not pin the old user when reset() rejects consent', () async {
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      var rejected = false;
      // opt_out_capturing_by_default: reset() clears consent, so posthog-js
      // only swaps in the sentinel when it builds the event.
      fake.setProperty(
          'reset'.toJS,
          (() {
            distinctId = 'reset-anonymous';
            rejected = true;
          }).toJS);
      fake.setProperty(
          'has_opted_out_capturing'.toJS, (() => rejected.toJS).toJS);
      for (final method in ['capture', 'captureException']) {
        fake.setProperty(
          method.toJS,
          ((JSAny? a, JSAny? b, [JSAny? c]) {
            if (rejected) distinctId = r'$posthog_cookieless';
            final props = b.dartify() as Map?;
            sentAs.add(props?['distinct_id'] as String? ?? distinctId);
          }).toJS,
        );
      }
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          await Future<void>.delayed(Duration.zero);
          return event;
        },
      ]));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.screen(screenName: 'Cart'),
        web.captureException(error: StateError('boom')),
      ];
      await web.reset();
      await Future.wait(sent);

      expect(sentAs, List.filled(3, r'$posthog_cookieless'));
    });

    test('does not pin a user captured under consent rejected elsewhere',
        () async {
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      // Another tab rejected the shared consent; this tab's cached id is
      // still the old user until opt-in resets it.
      var rejected = true;
      fake.setProperty(
          'has_opted_out_capturing'.toJS, (() => rejected.toJS).toJS);
      fake.setProperty(
          'opt_in_capturing'.toJS,
          (() {
            distinctId = 'new-user';
            rejected = false;
          }).toJS);
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) async {
          await Future<void>.delayed(Duration.zero);
          return event;
        },
      ]));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.screen(screenName: 'Cart'),
        web.captureException(error: StateError('boom')),
      ];
      await web.enable();
      await Future.wait(sent);

      expect(sentAs, ['new-user', 'new-user', 'new-user']);
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
