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
