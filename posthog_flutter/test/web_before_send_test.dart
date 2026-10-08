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

  group(r'$flutter_version',
      skip: const String.fromEnvironment('FLUTTER_VERSION').isEmpty
          ? 'Flutter < 3.32 does not report its version'
          : false, () {
    const flutterVersion = String.fromEnvironment('FLUTTER_VERSION');

    Map propertiesOf(String event) =>
        captures.lastWhere((c) => c['event'] == event)['properties'] as Map;

    Future<void> captureAll(PosthogFlutterWeb web,
        [Map<String, Object>? props]) async {
      await web.capture(eventName: 'checkout', properties: props);
      await web.screen(screenName: 'Home', properties: props);
      await web.captureException(error: StateError('boom'), properties: props);
    }

    test('is sent and visible to beforeSend', () async {
      final seen = <String, Object?>{};
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) {
          seen[event.event] = event.properties?[r'$flutter_version'];
          return event;
        },
      ]));

      await captureAll(web);

      expect(seen, {
        'checkout': flutterVersion,
        r'$screen': flutterVersion,
        r'$exception': flutterVersion,
      });
      for (final event in ['checkout', r'$screen', r'$exception']) {
        expect(propertiesOf(event)[r'$flutter_version'], flutterVersion);
      }
    });

    test('replaces a caller-set value', () async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token'));

      await captureAll(web, {r'$flutter_version': 'custom'});

      for (final event in ['checkout', r'$screen', r'$exception']) {
        expect(propertiesOf(event)[r'$flutter_version'], flutterVersion);
      }
    });

    for (final props in [
      <String, Object>{},
      <String, Object>{r'$flutter_version': 'caller'},
    ]) {
      test('stays removed when beforeSend removes it (caller props: $props)',
          () async {
        final web = PosthogFlutterWeb();
        await web.setup(PostHogConfig('test_token', beforeSend: [
          (event) {
            event.properties?.remove(r'$flutter_version');
            return event;
          },
        ]));

        await captureAll(web, props);

        expect(captures, hasLength(3));
        for (final capture in captures) {
          expect(capture['properties'] as Map,
              isNot(contains(r'$flutter_version')));
        }
      });
    }

    test('stays removed when beforeSend removes it and renames the event',
        () async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) {
          if (event.event == r'$screen' || event.event == r'$exception') {
            event.properties?.remove(r'$flutter_version');
            event.event = 'redacted_event';
          }
          return event;
        },
      ]));

      await web.screen(screenName: 'Home');
      await web.captureException(error: StateError('boom'));

      expect(captures.map((c) => c['event']),
          ['redacted_event', 'redacted_event']);
      for (final capture in captures) {
        expect(
            capture['properties'] as Map, isNot(contains(r'$flutter_version')));
      }
    });
  });
}
