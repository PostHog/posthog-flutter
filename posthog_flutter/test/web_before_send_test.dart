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

  for (final hooked in [false, true]) {
    test(
        'events reach posthog-js before a reset made right after them '
        '(${hooked ? 'with' : 'without'} beforeSend)', () async {
      final calls = <String>[];
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      fake.setProperty(
        'capture'.toJS,
        ((JSString event, [JSAny? a, JSAny? b]) => calls.add(event.toDart))
            .toJS,
      );
      fake.setProperty(
        'captureException'.toJS,
        (([JSAny? a, JSAny? b]) => calls.add('captureException')).toJS,
      );
      fake.setProperty('reset'.toJS, (([JSAny? a]) => calls.add('reset')).toJS);
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token',
          beforeSend: [if (hooked) (event) => event]));

      final sent = [
        web.capture(eventName: 'checkout'),
        web.screen(screenName: 'Cart'),
        web.captureException(error: StateError('boom')),
      ];
      await web.reset();
      await Future.wait(sent);

      expect(calls, ['checkout', r'$screen', 'captureException', 'reset']);
    });
  }

  test('a feature event looks up its flag and captures before a reset',
      () async {
    final calls = <String>[];
    final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
    fake.setProperty(
      'getFeatureFlagResult'.toJS,
      ((JSString key, [JSAny? options]) {
        calls.add('getFeatureFlagResult');
        return {'key': key.toDart, 'enabled': true}.jsify();
      }).toJS,
    );
    fake.setProperty(
      'capture'.toJS,
      ((JSString event, [JSAny? a, JSAny? b]) => calls.add(event.toDart)).toJS,
    );
    fake.setProperty('reset'.toJS, (([JSAny? a]) => calls.add('reset')).toJS);
    final web = PosthogFlutterWeb();
    await web.setup(PostHogConfig('test_token'));

    final sent = web.captureFeatureView(flag: 'checkout');
    await web.reset();
    await sent;

    expect(calls, ['getFeatureFlagResult', r'$feature_view', 'reset']);
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
