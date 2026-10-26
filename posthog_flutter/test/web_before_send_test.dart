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

  test('event options are sent as their legacy properties on web', () async {
    final web = PosthogFlutterWeb();
    await web.setup(PostHogConfig('test_token', beforeSend: [
      (event) {
        event.options = {...?event.options, 'cookieless_mode': true};
        return event;
      },
    ]));
    const options = {
      'disable_skew_correction': true,
      'product_tour_id': 'tour-1',
      'unknown_option': 'dropped',
    };

    await web.capture(
      eventName: 'tour step',
      properties: {r'$product_tour_id': 'from-property'},
      options: options,
    );
    await web.screen(screenName: 'Home', options: options);
    await web.captureException(error: StateError('boom'), options: options);

    expect(captures.map((c) => c['event']),
        ['tour step', r'$screen', r'$exception']);
    for (final capture in captures) {
      final properties = capture['properties'] as Map;
      expect(properties[r'$ignore_sent_at'], isTrue);
      expect(properties[r'$product_tour_id'], 'tour-1');
      expect(properties[r'$cookieless_mode'], isTrue);
      expect(properties, isNot(contains('unknown_option')));
    }
  });

  test('captureAi sends nothing on web and returns null', () async {
    final web = PosthogFlutterWeb();
    await web.setup(PostHogConfig('test_token'));

    expect(await web.captureAi(eventName: r'$ai_generation'), isNull);
    expect(captures, isEmpty);
  });
}
