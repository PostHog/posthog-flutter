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
  late String distinctId;

  setUp(() {
    captures.clear();
    final fake = JSObject();
    fake.setProperty(
      'capture'.toJS,
      ((JSString event, JSAny? properties, [JSAny? options]) {
        captures.add({
          'event': event.toDart,
          'properties': properties?.dartify(),
          'options': options?.dartify(),
        });
      }).toJS,
    );
    distinctId = 'first-user';
    fake.setProperty('get_distinct_id'.toJS, (() => distinctId.toJS).toJS);
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

  group('a hook that changes the user', () {
    final sends = <String, Future<void> Function(PosthogFlutterWeb)>{
      'capture': (web) => web.capture(eventName: 'checkout'),
      'screen': (web) => web.screen(screenName: 'Cart'),
      'captureException': (web) =>
          web.captureException(error: StateError('boom')),
    };

    sends.forEach((name, send) {
      test('keeps $name on the earlier user', () async {
        final web = PosthogFlutterWeb();
        await web.setup(PostHogConfig('test_token', beforeSend: [
          (event) {
            distinctId = 'next-user';
            return event;
          },
        ]));

        await send(web);

        final properties = captures.single['properties'] as Map;
        expect(properties['distinct_id'], 'first-user');
      });
    });

    test('leaves the user alone when the hook does not change it', () async {
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [(e) => e]));

      await web.capture(eventName: 'checkout');

      expect(captures.single['properties'], isNot(contains('distinct_id')));
    });
  });

  group('a hook that sets user properties without renaming', () {
    PostHogConfig hooked() => PostHogConfig('test_token', beforeSend: [
          (event) {
            event.userProperties = {'plan': 'pro'};
            event.userPropertiesSetOnce = {'first': 'yes'};
            return event;
          },
        ]);

    test('keeps them on a screen', () async {
      final web = PosthogFlutterWeb();
      await web.setup(hooked());

      await web.screen(screenName: 'Cart');

      expect(captures.single['event'], r'$screen');
      expect(captures.single['options'], {
        r'$set': {'plan': 'pro'},
        r'$set_once': {'first': 'yes'},
      });
    });

    test('keeps them on an exception', () async {
      final web = PosthogFlutterWeb();
      await web.setup(hooked());

      await web.captureException(error: StateError('boom'));

      final properties = captures.single['properties'] as Map;
      expect(properties[r'$set'], {'plan': 'pro'});
      expect(properties[r'$set_once'], {'first': 'yes'});
    });
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

  for (final hooked in [false, true]) {
    test(
        'feature events read the flag and reach posthog-js before a reset made '
        'right after them (${hooked ? 'with' : 'without'} beforeSend)',
        () async {
      final calls = <String>[];
      var variant = 'for-the-old-user';
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      fake.setProperty(
        'capture'.toJS,
        ((JSString event, JSAny? properties, [JSAny? options]) {
          final flagged = properties?.dartify() as Map?;
          calls.add('${event.toDart}:${flagged?['feature_flag_variant']}');
        }).toJS,
      );
      fake.setProperty(
        'getFeatureFlagResult'.toJS,
        ((JSString key, [JSAny? options]) => {
              'key': key.toDart,
              'enabled': true,
              'variant': variant,
            }.jsify()).toJS,
      );
      fake.setProperty(
        'reset'.toJS,
        (([JSAny? a]) {
          calls.add('reset');
          variant = 'for-the-new-user';
        }).toJS,
      );
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token',
          beforeSend: [if (hooked) (event) => event]));

      final sent = [
        web.captureFeatureView(flag: 'checkout'),
        web.captureFeatureInteraction(flag: 'checkout'),
      ];
      await web.reset();
      await Future.wait(sent);

      expect(calls, [
        r'$feature_view:for-the-old-user',
        r'$feature_interaction:for-the-old-user',
        'reset',
      ]);
    });
  }

  group('a hook that renames an event', () {
    final renames = <String, Future<void> Function(PosthogFlutterWeb)>{
      'capture': (web) => web.capture(eventName: 'original'),
      'screen': (web) => web.screen(screenName: 'Checkout'),
      'captureException': (web) =>
          web.captureException(error: StateError('boom')),
    };

    renames.forEach((name, send) {
      test('$name runs the hook once and keeps its user properties', () async {
        var runs = 0;
        final web = PosthogFlutterWeb();
        await web.setup(PostHogConfig('test_token', beforeSend: [
          (event) {
            runs++;
            event.event = 'renamed';
            event.userProperties = {'source': 'hook'};
            return event;
          },
        ]));

        await send(web);

        expect(runs, 1);
        expect(captures.single['event'], 'renamed');
        final options = captures.single['options'] as Map;
        expect(options[r'$set'], {'source': 'hook'});
      });
    });
  });

  group('a hook that calls the SDK', () {
    test('can capture another event without running forever', () async {
      final web = PosthogFlutterWeb();
      final seen = <String>[];
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) {
          seen.add(event.event);
          if (event.event == 'outer') web.capture(eventName: 'inner');
          return event;
        },
      ]));

      await web.capture(eventName: 'outer');

      expect(seen, ['outer', 'inner']);
      expect(captures.map((c) => c['event']), ['inner', 'outer']);
    });

    test('an unawaited getter inside the hook does not delay the event',
        () async {
      final calls = <String>[];
      final fake = globalContext.getProperty<JSObject>('posthog'.toJS);
      fake.setProperty(
        'capture'.toJS,
        ((JSString event, [JSAny? a, JSAny? b]) => calls.add(event.toDart))
            .toJS,
      );
      fake.setProperty('reset'.toJS, (([JSAny? a]) => calls.add('reset')).toJS);
      fake.setProperty('has_opted_out_capturing'.toJS, (() => false.toJS).toJS);
      final web = PosthogFlutterWeb();
      await web.setup(PostHogConfig('test_token', beforeSend: [
        (event) {
          web.isOptOut();
          return event;
        },
      ]));

      final sent = web.capture(eventName: 'checkout');
      await web.reset();
      await sent;

      expect(calls, ['checkout', 'reset']);
    });
  });

  test('a change made after the hook returned is not sent', () async {
    final web = PosthogFlutterWeb();
    await web.setup(PostHogConfig('test_token', beforeSend: [
      (event) {
        Future<void>.delayed(Duration.zero, () {
          event.properties?['late'] = true;
        });
        return event;
      },
    ]));

    await web.capture(eventName: 'checkout', properties: {'plan': 'pro'});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect((captures.single['properties'] as Map).containsKey('late'), isFalse);
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
