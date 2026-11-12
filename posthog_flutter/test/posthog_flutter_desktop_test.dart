import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/queue_worker.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'package:posthog_flutter/src/feature_flag_result.dart';
import 'package:posthog_flutter/src/feature_flags_listeners.dart';
import 'package:posthog_flutter/src/feature_flags_loaded.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_desktop_app_info.dart';
import 'package:posthog_flutter/src/posthog_event.dart';
import 'package:posthog_flutter/src/posthog_flutter_desktop.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import 'core/test_client.dart';
import 'posthog_api_fake.dart';

// No TestWidgetsFlutterBinding here: the test binding replaces dart:io's
// HttpClient with a stub that answers 400 to everything, and these tests
// exercise the real HTTP path against a local server.
void main() {
  /// Create it before the platform that uses it: tear-downs run in reverse
  /// order, and Windows cannot delete a directory whose lock file the
  /// platform still holds open.
  Directory createAppDirectory() {
    final dir = Directory.systemTemp.createTempSync('posthog_flutter_desktop');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  /// A platform for an app that keeps its state in [appDirectory], a new
  /// temporary directory by default, whose build recorded [appInfo] and
  /// that runs in [timezone].
  PosthogFlutterDesktop createPlatform({
    Directory? appDirectory,
    Future<String?> Function()? resolveAppDirectory,
    DesktopAppInfo appInfo = const DesktopAppInfo(),
    String? timezone,
  }) {
    final directory = appDirectory ?? createAppDirectory();
    final platform = PosthogFlutterDesktop(
      appDirectory: resolveAppDirectory ?? () async => directory.path,
      appInfo: appInfo,
      timezone: timezone,
    );
    addTearDown(platform.close);
    return platform;
  }

  PostHogConfig configFor(
    LocalPostHogServer server, {
    String projectToken = 'test_project_token',
  }) {
    return PostHogConfig(projectToken)
      ..host = server.url
      ..flushAt = 1;
  }

  Future<PosthogFlutterDesktop> setUpPlatform(PostHogConfig config) async {
    final platform = createPlatform();
    await platform.setup(config);
    return platform;
  }

  group('PosthogFlutterDesktop before setup', () {
    late PosthogFlutterDesktop platform;

    setUp(() {
      platform = createPlatform();
    });

    final callsByName = <String, Future<void> Function(PosthogFlutterDesktop)>{
      'capture': (platform) => platform.capture(eventName: 'event'),
      'screen': (platform) => platform.screen(screenName: 'Home'),
      'identify': (platform) => platform.identify(userId: 'user-1'),
      'group': (platform) =>
          platform.group(groupType: 'company', groupKey: 'acme'),
      'alias': (platform) => platform.alias(alias: 'other-user'),
      'flush': (platform) => platform.flush(),
      'reset': (platform) => platform.reset(),
      'close': (platform) => platform.close(),
    };

    for (final entry in callsByName.entries) {
      test('${entry.key} is ignored with a debug warning', () async {
        final lines = await _printsOf(() => entry.value(platform));

        expect(lines, [contains('${entry.key} ignored')]);
      });
    }

    final nullReadsByName =
        <String, Future<Object?> Function(PosthogFlutterDesktop)>{
      'getFeatureFlag': (platform) => platform.getFeatureFlag(key: 'flag'),
      'getFeatureFlagResult': (platform) =>
          platform.getFeatureFlagResult(key: 'flag'),
      'getAllFeatureFlags': (platform) => platform.getAllFeatureFlags(),
      'getSessionId': (platform) => platform.getSessionId(),
    };

    for (final entry in nullReadsByName.entries) {
      test('${entry.key} returns null', () async {
        expect(await entry.value(platform), isNull);
      });
    }

    test('getDistinctId returns an empty string', () async {
      expect(await platform.getDistinctId(), '');
    });

    test('isFeatureEnabled returns false', () async {
      expect(await platform.isFeatureEnabled('flag'), isFalse);
    });

    test('isFeatureEnabled returns the default', () async {
      expect(
          await platform.isFeatureEnabled('flag', defaultValue: true), isTrue);
    });

    test('isOptOut reports opted out', () async {
      expect(await platform.isOptOut(), isTrue);
    });
  });

  group('Windows and Linux support disabled', () {
    test('skips storage, requests and capture until enabled setup', () async {
      final server = await LocalPostHogServer.start();
      final directory = createAppDirectory();
      var directoryLookups = 0;
      final platform = createPlatform(
        appDirectory: directory,
        resolveAppDirectory: () async {
          directoryLookups++;
          return directory.path;
        },
      );
      final config = configFor(server)..enableWindowsAndLinux = false;

      await platform.setup(config);
      await platform.capture(eventName: 'disabled event');
      await platform.identify(userId: 'disabled user');
      await platform.optIn();
      await platform.reloadFeatureFlags();
      await platform.flush();
      expect(await platform.getFeatureFlag(key: 'flag'), isNull);
      expect(await platform.getDistinctId(), isEmpty);
      expect(directoryLookups, 0);
      expect(directory.listSync(), isEmpty);
      expect(server.requests, isEmpty);

      await platform.close();
      config.enableWindowsAndLinux = true;
      await platform.setup(config);
      await platform.capture(eventName: 'enabled event');
      await server.waitForEvent('enabled event');
      await server.waitForFlagsRequest(0);
      expect(directoryLookups, 1);
      expect(directory.listSync(), isNotEmpty);
      expect(server.eventNames, isNot(contains('disabled event')));
    });
  });

  group('PosthogFlutterDesktop.capture', () {
    test('delivers the event with properties and person properties', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(
        eventName: 'purchase completed',
        properties: {'plan': 'pro'},
        userProperties: {'name': 'Max'},
        userPropertiesSetOnce: {'signup_channel': 'organic'},
      );

      final event = await server.waitForEvent('purchase completed');
      final properties = _propertiesOf(event);
      expect(properties['plan'], 'pro');
      expect(properties[r'$set'], {'name': 'Max'});
      expect(properties[r'$set_once'], {'signup_channel': 'organic'});
    });

    test('drops an event without a name, also one a callback renames to none',
        () async {
      final server = await LocalPostHogServer.start();
      final seenEventNames = <String>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seenEventNames.add(event.event);
            if (event.event == 'renamed away') event.event = '';
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      final lines = await _printsOf(() async {
        await platform.capture(eventName: '');
        await platform.capture(eventName: 'renamed away');
      });
      await platform.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      expect(server.eventNames, ['sentinel event']);
      expect(seenEventNames, ['renamed away', 'sentinel event'],
          reason: 'an event without a name is dropped before the callbacks');
      expect(lines, [
        contains('empty event name'),
        contains('empty event name'),
      ]);
    });

    test(r'merges a legacy $set in properties, explicit keys winning',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(
        eventName: 'legacy merge',
        properties: {
          r'$set': {'plan': 'legacy', 'team': 'core'},
        },
        userProperties: {'plan': 'pro'},
      );

      final event = await server.waitForEvent('legacy merge');
      expect(_propertiesOf(event)[r'$set'], {'plan': 'pro', 'team': 'core'});
    });

    test(r'a beforeSend that removes a legacy $set keeps it off the event',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) => event..properties?.remove(r'$set'),
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'redacted',
        properties: {
          r'$set': {'email': 'a@b.c'},
        },
      );

      final event = await server.waitForEvent('redacted');
      expect(_propertiesOf(event), isNot(contains(r'$set')));
    });

    test(r'sends $app_language', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.setAppLanguage('fr');
      await platform.capture(eventName: 'translated');

      final event = await server.waitForEvent('translated');
      expect(_propertiesOf(event)[r'$app_language'], 'fr');
    });

    test(r'reports the platform language as $locale', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(eventName: 'localized event');

      final event = await server.waitForEvent('localized event');
      expect(
        _propertiesOf(event)[r'$locale'],
        PlatformDispatcher.instance.locale.toLanguageTag(),
      );
    });

    test('does not admit a capture made while opted out', () async {
      final server = await LocalPostHogServer.start();
      final callbackEvents = <String>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            callbackEvents.add(event.event);
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.optOut();
      await platform.capture(eventName: 'blocked capture');
      await platform.optIn();
      await platform.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      expect(server.eventNames, ['sentinel event']);
      expect(callbackEvents, ['sentinel event']);
    });

    test(r'reports the time zone as $timezone and to /flags', () async {
      final server = await LocalPostHogServer.start();
      final platform = createPlatform(timezone: 'Europe/Berlin');
      await platform.setup(configFor(server));

      await platform.capture(eventName: 'zoned event');

      final event = await server.waitForEvent('zoned event');
      expect(_propertiesOf(event)[r'$timezone'], 'Europe/Berlin');
      final flags = await server.waitForFlagsRequest(0);
      expect(flags['timezone'], 'Europe/Berlin');
    });

    test('leaves the time zone out when it is unknown', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(eventName: 'unzoned event');

      final event = await server.waitForEvent('unzoned event');
      expect(_propertiesOf(event), isNot(contains(r'$timezone')));
      final flags = await server.waitForFlagsRequest(0);
      expect(flags, isNot(contains('timezone')));
    });

    test(r'reports $recording_status disabled unless the event sets it',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.identify(userId: 'user-1');
      await platform.capture(
        eventName: 'replay event',
        properties: {r'$recording_status': 'active'},
      );

      final identify = await server.waitForEvent(r'$identify');
      expect(_propertiesOf(identify)[r'$recording_status'], 'disabled');
      final captured = await server.waitForEvent('replay event');
      expect(_propertiesOf(captured)[r'$recording_status'], 'active');
    });
  });

  <String, Future<void> Function(PosthogFlutterDesktop)>{
    'capture': (platform) => platform.capture(eventName: 'event'),
    'screen': (platform) => platform.screen(screenName: 'screen'),
    'captureException': (platform) =>
        platform.captureException(error: StateError('error')),
    'identify': (platform) => platform.identify(userId: 'user'),
    'alias': (platform) => platform.alias(alias: 'alias'),
    'group': (platform) =>
        platform.group(groupType: 'company', groupKey: 'acme'),
    'setPersonProperties': (platform) =>
        platform.setPersonProperties(userPropertiesToSet: {'plan': 'pro'}),
  }.forEach((name, call) {
    test('an awaited $name completes once the event is on disk', () async {
      final server = await LocalPostHogServer.start();
      final worker = GatedWorker();
      final defaultWorker = QueueWorker.defaultWorker;
      QueueWorker.defaultWorker = () => worker;
      addTearDown(() => QueueWorker.defaultWorker = defaultWorker);
      final platform = await setUpPlatform(configFor(server));
      worker.writeGate = Completer();

      var done = false;
      final completed = call(platform).then((_) => done = true);
      await pumpEventQueue();
      expect(done, isFalse);

      worker.writeGate!.complete();
      await completed;
    });
  });

  test('a queue file job failing on close does not stop the next setup',
      () async {
    final server = await LocalPostHogServer.start();
    final worker = _LateFailingDeletes();
    final defaultWorker = QueueWorker.defaultWorker;
    QueueWorker.defaultWorker = () => worker;
    addTearDown(() => QueueWorker.defaultWorker = defaultWorker);
    final platform = await setUpPlatform(configFor(server));
    await platform.capture(eventName: 'first');
    await server.waitForEvent('first');

    // Fails only once close() has given up on the flush and awaits settled.
    final closed = platform.close();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    worker.gate.complete();
    await closed;

    worker.fail = false;
    await platform.setup(configFor(server));
    await platform.capture(eventName: 'second');

    await server.waitForEvent('second');
  });

  test('close gives up on stalled file work, and the next setup waits for it',
      () async {
    final server = await LocalPostHogServer.start();
    final worker = GatedWorker();
    final defaultWorker = QueueWorker.defaultWorker;
    QueueWorker.defaultWorker = () => worker;
    addTearDown(() => QueueWorker.defaultWorker = defaultWorker);
    final platform = await setUpPlatform(configFor(server));

    worker.writeGate = Completer();
    unawaited(platform.capture(eventName: 'stalled'));
    await platform.close();

    var ready = false;
    final setup = platform.setup(configFor(server)).then((_) => ready = true);
    await pumpEventQueue();
    expect(ready, isFalse);

    worker.writeGate!.complete();
    await setup;
  });

  group('PosthogFlutterDesktop.screen', () {
    test(r'delivers $screen with the screen name property', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.screen(
        screenName: 'Home Screen',
        properties: {'tab': 'primary'},
      );

      final event = await server.waitForEvent(r'$screen');
      final properties = _propertiesOf(event);
      expect(properties[r'$screen_name'], 'Home Screen');
      expect(properties['tab'], 'primary');
    });

    test(r'the screen name wins over a $screen_name property', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.screen(
        screenName: 'Checkout',
        properties: {r'$screen_name': 'Cart'},
      );
      await platform.capture(eventName: 'after screen');

      final screen = await server.waitForEvent(r'$screen');
      expect(_propertiesOf(screen)[r'$screen_name'], 'Checkout');
      final after = await server.waitForEvent('after screen');
      expect(_propertiesOf(after)[r'$screen_name'], 'Checkout');
    });

    test('does nothing while opted out', () async {
      final server = await LocalPostHogServer.start();
      final seenEventNames = <String>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seenEventNames.add(event.event);
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.optOut();
      await platform.screen(screenName: 'Hidden');
      await platform.optIn();
      await platform.capture(eventName: 'sentinel event');

      final event = await server.waitForEvent('sentinel event');
      expect(server.eventNames, ['sentinel event']);
      expect(seenEventNames, ['sentinel event'],
          reason: 'no callback runs for a screen while opted out');
      expect(_propertiesOf(event), isNot(contains(r'$screen_name')),
          reason: 'the screen did not become the current one');
    });

    test('runs the hook once when it renames a screen event', () async {
      final server = await LocalPostHogServer.start();
      var callbackCount = 0;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            callbackCount++;
            event.event = 'renamed screen';
            event.userProperties = {'source': 'screen hook'};
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.screen(screenName: 'Checkout');

      final event = await server.waitForEvent('renamed screen');
      expect(callbackCount, 1);
      expect(_propertiesOf(event)[r'$set'], {'source': 'screen hook'});
    });

    test('a callback that removes the screen name keeps it off the events',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            event.properties = {'scrubbed': true};
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.screen(screenName: 'Home Screen');
      await platform.capture(eventName: 'after screen');

      final event = await server.waitForEvent(r'$screen');
      final properties = _propertiesOf(event);
      expect(properties, isNot(contains(r'$screen_name')));
      expect(properties['scrubbed'], isTrue);
      final after = await server.waitForEvent('after screen');
      expect(_propertiesOf(after), isNot(contains(r'$screen_name')));
    });

    test('sends a non-string screen name a callback leaves', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) => event..properties?[r'$screen_name'] = 42,
        ];
      final platform = await setUpPlatform(config);

      await platform.screen(screenName: 'Home Screen');

      final event = await server.waitForEvent(r'$screen');
      expect(_propertiesOf(event)[r'$screen_name'], 42);
    });

    test('later events carry the last screen name', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.screen(screenName: 'Checkout');
      await platform.capture(eventName: 'after screen');
      await platform.identify(userId: 'user-1');

      final captured = await server.waitForEvent('after screen');
      expect(_propertiesOf(captured)[r'$screen_name'], 'Checkout');
      final identify = await server.waitForEvent(r'$identify');
      expect(_propertiesOf(identify)[r'$screen_name'], 'Checkout');
    });

    test('an explicit screen name wins over the last screen', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.screen(screenName: 'Checkout');
      await platform.capture(
        eventName: 'explicit screen',
        properties: {r'$screen_name': 'Cart'},
      );

      final event = await server.waitForEvent('explicit screen');
      expect(_propertiesOf(event)[r'$screen_name'], 'Cart');
    });

    test('reset forgets the last screen', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.screen(screenName: 'Checkout');
      await platform.reset();
      await platform.capture(eventName: 'after reset');

      final event = await server.waitForEvent('after reset');
      expect(_propertiesOf(event), isNot(contains(r'$screen_name')));
    });

    test('drops a screen with an empty name', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.screen(screenName: 'Checkout');
      await platform.screen(screenName: '');
      await platform.capture(eventName: 'sentinel event');

      final event = await server.waitForEvent('sentinel event');
      expect(
          server.eventNames.where((name) => name == r'$screen'), hasLength(1));
      expect(_propertiesOf(event)[r'$screen_name'], 'Checkout');
    });
  });

  group('beforeSend hook', () {
    group('that calls the SDK', () {
      test('can capture another event without running forever', () async {
        final server = await LocalPostHogServer.start();
        final seen = <String>[];
        late final PosthogFlutterDesktop platform;
        final config = configFor(server)
          ..beforeSend = [
            (event) {
              seen.add(event.event);
              if (event.event == 'outer') {
                platform.capture(eventName: 'inner');
              }
              return event;
            },
          ];
        platform = await setUpPlatform(config);

        await platform.capture(eventName: 'outer');
        await server.waitForEvent('inner');
        await server.waitForEvent('outer');

        expect(seen, ['outer', 'inner']);
      });

      final calls = <String, Future<void> Function(PosthogFlutterDesktop)>{
        'reset': (platform) => platform.reset(),
        'identify': (platform) => platform.identify(userId: 'user-1'),
        'optOut': (platform) => platform.optOut(),
        'getDistinctId': (platform) => platform.getDistinctId(),
        'getFeatureFlag': (platform) => platform.getFeatureFlag(key: 'flag'),
      };

      calls.forEach((name, call) {
        test('$name inside the hook does not deadlock', () async {
          final server = await LocalPostHogServer.start();
          late final PosthogFlutterDesktop platform;
          final config = configFor(server)
            ..beforeSend = [
              (event) {
                if (event.event == 'trigger') call(platform);
                return event;
              },
            ];
          platform = await setUpPlatform(config);

          await platform
              .capture(eventName: 'trigger')
              .timeout(const Duration(seconds: 2));
        });
      });
    });

    for (final (name, call)
        in <(String, Future<void> Function(PosthogFlutterDesktop))>[
      ('reset', (platform) => platform.reset()),
      ('identify', (platform) => platform.identify(userId: 'user-1')),
    ]) {
      test('$name inside the hook keeps the event on the earlier user',
          () async {
        final server = await LocalPostHogServer.start();
        late final PosthogFlutterDesktop platform;
        final config = configFor(server)
          ..beforeSend = [
            (event) {
              if (event.event == 'trigger') call(platform);
              return event;
            },
          ];
        platform = await setUpPlatform(config);
        final firstUser = await platform.getDistinctId();

        await platform.capture(eventName: 'trigger');

        final event = await server.waitForEvent('trigger');
        expect(event['distinct_id'], firstUser);
        expect(await platform.getDistinctId(), isNot(firstUser));
      });
    }

    test('reset inside the hook leaves an identified event person-processed',
        () async {
      final server = await LocalPostHogServer.start();
      late final PosthogFlutterDesktop platform;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == 'trigger') platform.reset();
            return event;
          },
        ];
      platform = await setUpPlatform(config);
      await platform.identify(userId: 'user-1');

      await platform.capture(eventName: 'trigger');

      final event = await server.waitForEvent('trigger');
      expect(event['distinct_id'], 'user-1');
      expect(_optionsOf(event), isNot(contains('process_person_profile')));
    });

    test('identify inside the hook leaves an anonymous event personless',
        () async {
      final server = await LocalPostHogServer.start();
      late final PosthogFlutterDesktop platform;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == 'trigger') {
              platform.identify(userId: 'user-1');
            }
            return event;
          },
        ];
      platform = await setUpPlatform(config);

      await platform.capture(eventName: 'trigger');

      final event = await server.waitForEvent('trigger');
      expect(_optionsOf(event)['process_person_profile'], isFalse);
    });

    test('reset inside the hook keeps the screen from the next user', () async {
      final server = await LocalPostHogServer.start();
      late final PosthogFlutterDesktop platform;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == r'$screen') platform.reset();
            return event;
          },
        ];
      platform = await setUpPlatform(config);

      await platform.screen(screenName: 'Checkout');
      await platform.capture(eventName: 'after reset');

      final event = await server.waitForEvent('after reset');
      expect(_propertiesOf(event), isNot(contains(r'$screen_name')));
    });

    test('identify inside the hook keeps the screen for later events',
        () async {
      final server = await LocalPostHogServer.start();
      late final PosthogFlutterDesktop platform;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == r'$screen') {
              platform.identify(userId: 'user-1');
            }
            return event;
          },
        ];
      platform = await setUpPlatform(config);

      await platform.screen(screenName: 'Checkout');
      await platform.capture(eventName: 'after identify');

      final event = await server.waitForEvent('after identify');
      expect(_propertiesOf(event)[r'$screen_name'], 'Checkout');
    });

    test('optOut inside the hook drops the event', () async {
      final server = await LocalPostHogServer.start();
      late final PosthogFlutterDesktop platform;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == 'trigger') platform.optOut();
            return event;
          },
        ];
      platform = await setUpPlatform(config);

      await platform.capture(eventName: 'trigger');
      await platform.optIn();
      await platform.capture(eventName: 'after');
      await server.waitForEvent('after');

      expect(server.eventNames, isNot(contains('trigger')));
    });

    test('calls after a burst of events apply in order', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)..beforeSend = [(event) => event];
      final platform = await setUpPlatform(config);
      final firstUser = await platform.getDistinctId();

      final sent = [
        for (var i = 0; i < 100; i++) platform.capture(eventName: 'event $i'),
        platform.reset(),
        platform.capture(eventName: 'after reset'),
      ];
      await Future.wait(sent);

      final last = await server.waitForEvent('event 99');
      expect(last['distinct_id'], firstUser);
      final after = await server.waitForEvent('after reset');
      expect(after['distinct_id'], isNot(firstUser));
    });

    test('dropping an event keeps it off the wire', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) => event.event == 'dropped event' ? null : event,
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(eventName: 'dropped event');
      await platform.capture(eventName: 'sentinel event');

      // Events are delivered in capture order, so once the sentinel arrived
      // the dropped event can no longer be in flight.
      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains('dropped event')));
    });

    test(
        'a callback sees the uuid, distinct id and timestamp, and can change '
        'the distinct id and timestamp but not the uuid', () async {
      final server = await LocalPostHogServer.start();
      PostHogEvent? seen;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seen = PostHogEvent(
              event: event.event,
              uuid: event.uuid,
              distinctId: event.distinctId,
              timestamp: event.timestamp,
            );
            return PostHogEvent(
              event: event.event,
              properties: event.properties,
              distinctId: 'changed-user',
              timestamp: DateTime.utc(2025, 1, 2, 3, 4, 5, 678),
            );
          },
        ];
      final platform = await setUpPlatform(config);
      final distinctId = await platform.getDistinctId();

      await platform.capture(eventName: 'identity');

      final event = await server.waitForEvent('identity');
      expect(seen!.uuid, isNotNull);
      expect(seen!.distinctId, distinctId);
      expect(seen!.timestamp, isNotNull);
      expect(event['uuid'], seen!.uuid);
      expect(event['distinct_id'], 'changed-user');
      expect(event['timestamp'], '2025-01-02T03:04:05.678Z');
    });

    test('a blank distinct id from a callback keeps the current one', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [(event) => event..distinctId = '  '];
      final platform = await setUpPlatform(config);
      final distinctId = await platform.getDistinctId();

      await platform.capture(eventName: 'blank');

      final event = await server.waitForEvent('blank');
      expect(event['distinct_id'], distinctId);
    });

    test('modifications made by a callback are delivered', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            event.event = 'renamed event';
            event.properties = {...?event.properties, 'amended': true};
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'original event',
        properties: {'plan': 'pro'},
      );

      final event = await server.waitForEvent('renamed event');
      final properties = _propertiesOf(event);
      expect(properties['plan'], 'pro');
      expect(properties['amended'], isTrue);
      expect(server.eventNames, isNot(contains('original event')));
    });

    test('a callback editing a registered nested map leaves later events alone',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == 'mutate') {
              final metadata = event.properties?['metadata'];
              if (metadata is Map) metadata['plan'] = 'pro';
            }
            return event;
          },
        ];
      final platform = await setUpPlatform(config);
      await platform.register('metadata', {'plan': 'free'});

      await platform.capture(eventName: 'mutate');
      await platform.capture(eventName: 'after');

      final mutated = _propertiesOf(await server.waitForEvent('mutate'));
      final after = _propertiesOf(await server.waitForEvent('after'));
      expect(mutated['metadata'], {'plan': 'pro'});
      expect(after['metadata'], {'plan': 'free'});
    });

    test('a callback can rewrite the person properties', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) => event..userProperties = {'plan': 'enterprise'},
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'upgraded',
        userProperties: {'plan': 'pro'},
      );

      final event = await server.waitForEvent('upgraded');
      expect(_propertiesOf(event)[r'$set'], {'plan': 'enterprise'});
    });

    test('flag evaluation gets the person properties the callbacks keep',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..preloadFeatureFlags = false
        ..beforeSend = [
          (event) {
            if (event.event == 'dropped') return null;
            return event
              ..userProperties = {'email': 'redacted'}
              ..userPropertiesSetOnce = null;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'redacted',
        userProperties: {'email': 'user@example.com'},
        userPropertiesSetOnce: {'first_seen': 'secret'},
      );
      await platform.capture(
        eventName: 'dropped',
        userProperties: {'dropped': 'secret'},
      );
      await platform.reloadFeatureFlags();

      final personProperties = Map<String, Object?>.from(
        server.flagsRequests.single.body['person_properties']! as Map,
      );
      expect(personProperties, containsPair('email', 'redacted'));
      expect(personProperties, isNot(contains('first_seen')));
      expect(personProperties, isNot(contains('dropped')));
    });

    test(
        'person properties of an event a callback sends for another distinct '
        'id stay out of flag evaluation', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..preloadFeatureFlags = false
        ..beforeSend = [(event) => event..distinctId = 'other-user'];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'other',
        userProperties: {'email': 'other@example.com'},
      );
      await platform.reloadFeatureFlags();

      final event = await server.waitForEvent('other');
      expect(event['distinct_id'], 'other-user');
      final personProperties = Map<String, Object?>.from(
        server.flagsRequests.single.body['person_properties']! as Map,
      );
      expect(personProperties, isNot(contains('email')));
    });

    test(
        'person properties of an event a callback sends for another distinct '
        'id leave person processing off for the current user', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == 'other') event.distinctId = 'other-user';
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'other',
        userProperties: {'email': 'other@example.com'},
      );
      await platform.capture(eventName: 'next');

      final event = await server.waitForEvent('other');
      expect(event['distinct_id'], 'other-user');
      final next = await server.waitForEvent('next');
      expect(_optionsOf(next)['process_person_profile'], isFalse);
    });

    test('a dropped person update does not turn on person processing',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) => event.event == 'dropped' ? null : event,
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'dropped',
        userProperties: {'email': 'user@example.com'},
      );
      await platform.capture(eventName: 'after drop');

      final event = await server.waitForEvent('after drop');
      expect(_optionsOf(event)['process_person_profile'], isFalse);
    });

    test('removing person properties leaves person processing as prepared',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [(event) => event..userProperties = null];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'redacted',
        userProperties: {'email': 'user@example.com'},
      );

      final event = await server.waitForEvent('redacted');
      expect(_optionsOf(event), isNot(contains('process_person_profile')));
    });

    test('person properties a callback adds leave the event personless',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) => event..userProperties = {'email': 'user@example.com'},
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(eventName: 'signed up');

      final event = await server.waitForEvent('signed up');
      expect(_optionsOf(event)['process_person_profile'], isFalse);
      expect(_propertiesOf(event)[r'$set'], {'email': 'user@example.com'});
    });

    test('person properties a callback adds leave later events personless',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == 'signed up') {
              event.userProperties = {'email': 'user@example.com'};
            }
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(eventName: 'signed up');
      await platform.capture(eventName: 'next');

      final next = await server.waitForEvent('next');
      expect(_optionsOf(next)['process_person_profile'], isFalse);
    });

    test(
        'removing person properties keeps person processing on for later events',
        () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [(event) => event..userProperties = null];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'redacted',
        userProperties: {'email': 'user@example.com'},
      );
      await platform.capture(eventName: 'next');

      final next = await server.waitForEvent('next');
      expect(_optionsOf(next), isNot(contains('process_person_profile')));
    });

    test('a callback can turn person processing back on', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) => event
            ..userProperties = null
            ..options = {'process_person_profile': true},
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'redacted',
        userProperties: {'email': 'user@example.com'},
      );

      final event = await server.waitForEvent('redacted');
      expect(_optionsOf(event)['process_person_profile'], isTrue);
    });

    test('a throwing callback drops the event and stops the chain', () async {
      final server = await LocalPostHogServer.start();
      final callOrder = <String>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            if (event.event == 'failing event') callOrder.add('transform');
            event.properties = {...?event.properties, 'scrubbed': true};
            return event;
          },
          (event) {
            if (event.event != 'failing event') return event;
            callOrder.add('throw');
            throw StateError('broken callback');
          },
          (event) {
            if (event.event == 'failing event') callOrder.add('after throw');
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await expectLater(
        platform.capture(eventName: 'failing event'),
        completes,
      );
      await platform.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains('failing event')));
      expect(callOrder, ['transform', 'throw']);
    });

    test('callbacks see and change the properties and options the SDK adds',
        () async {
      final server = await LocalPostHogServer.start();
      PostHogEvent? seen;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seen = PostHogEvent(
              event: event.event,
              properties: {...?event.properties},
              options: {...?event.options},
            );
            event.properties = {
              ...?event.properties,
              r'$device_type': 'Kiosk',
            }..remove(r'$os_name');
            event.options = null;
            return event;
          },
        ];
      final platform = await setUpPlatform(config);
      await platform.register('plan', 'free');

      await platform.capture(
        eventName: 'context event',
        properties: {'plan': 'pro'},
      );

      final event = await server.waitForEvent('context event');
      final seenProperties = seen!.properties!;
      expect(seenProperties, containsPair('plan', 'pro'),
          reason: 'the event wins over a registered property');
      expect(seenProperties, containsPair(r'$device_type', 'Desktop'));
      expect(seenProperties, contains(r'$os_name'));
      expect(seenProperties, contains(r'$session_id'));
      expect(seenProperties, contains(r'$lib'));
      expect(seen!.options, {'process_person_profile': false});
      // The SDK adds nothing back after the hook ran.
      final properties = _propertiesOf(event);
      expect(properties, containsPair(r'$device_type', 'Kiosk'));
      expect(properties, isNot(contains(r'$os_name')));
      expect(event, isNot(contains('options')));
      expect(event['session_id'], isA<String>());
    });

    test('callbacks see registered options and can remove them', () async {
      final server = await LocalPostHogServer.start();
      Map<String, Object?>? seen;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seen = {...?event.options};
            event.options = {...?event.options}..remove('cookieless_mode');
            return event;
          },
        ];
      final platform = await setUpPlatform(config);
      await platform.registerOptions(
          {'cookieless_mode': true, 'disable_skew_correction': true});

      await platform.capture(
        eventName: 'registered options event',
        options: {'disable_skew_correction': false},
      );

      final event = await server.waitForEvent('registered options event');
      expect(seen, containsPair('cookieless_mode', true));
      expect(seen, containsPair('disable_skew_correction', false),
          reason: "the event's own option wins over a registered one");
      final sentOptions = event['options'] as Map;
      expect(sentOptions, isNot(contains('cookieless_mode')),
          reason: 'the SDK adds nothing back after the hook ran');
      expect(sentOptions, containsPair('disable_skew_correction', false));
    });

    test('properties the callbacks remove stay removed', () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      Map<String, Object?>? seen;
      final removed = [
        r'$feature/variant-flag',
        r'$active_feature_flags',
        r'$recording_status',
      ];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seen = {...?event.properties};
            event.properties = {...?event.properties}
              ..removeWhere((key, _) => removed.contains(key));
            return event;
          },
        ];
      final platform = await setUpPlatform(config);
      await flagsLoaded;

      await platform.capture(eventName: 'scrubbed');

      final properties = _propertiesOf(await server.waitForEvent('scrubbed'));
      expect(seen!.keys, containsAll(removed));
      for (final key in removed) {
        expect(properties, isNot(contains(key)));
      }
    });

    test('the event time is taken before the callbacks run', () async {
      final server = await LocalPostHogServer.start();
      late DateTime hookStarted;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            hookStarted = DateTime.now().toUtc();
            // Real wait: the event must not take the time it is queued.
            final waited = Stopwatch()..start();
            while (waited.elapsedMilliseconds < 50) {}
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(eventName: 'slow hook');

      final event = await server.waitForEvent('slow hook');
      final timestamp = DateTime.parse(event['timestamp']! as String);
      expect(timestamp.isAfter(hookStarted), isFalse);
    });

    test('SDK-internal events bypass the callbacks', () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final seenEventNames = <String>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seenEventNames.add(event.event);
            return event;
          },
        ];
      final platform = await setUpPlatform(config);
      await flagsLoaded;

      await platform.getFeatureFlagResult(key: 'variant-flag');
      await platform.capture(eventName: 'user event');

      await server.waitForEvent(r'$feature_flag_called');
      await server.waitForEvent('user event');
      // Both events reached the wire, but only the user-initiated capture
      // passed through the hook.
      expect(seenEventNames, ['user event']);
    });
  });

  group('PosthogFlutterDesktop.captureException', () {
    test(r'delivers $exception with a processed exception list', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      late Object error;
      late StackTrace stackTrace;
      try {
        throw StateError('desktop failure');
      } catch (e, s) {
        error = e;
        stackTrace = s;
      }
      await platform.captureException(error: error, stackTrace: stackTrace);

      final event = await server.waitForEvent(r'$exception');
      final properties = _propertiesOf(event);
      expect(properties[r'$exception_level'], 'error');

      final exceptionList = properties[r'$exception_list']! as List;
      final exception = Map<String, Object?>.from(exceptionList.first as Map);
      expect(exception['type'], 'StateError');
      expect(exception['value'], 'Bad state: desktop failure');

      final stacktrace =
          Map<String, Object?>.from(exception['stacktrace']! as Map);
      expect(stacktrace['frames'], isNotEmpty);
    });

    test('does not admit an exception made while opted out', () async {
      final server = await LocalPostHogServer.start();
      final callbackEvents = <String>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            callbackEvents.add(event.event);
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.optOut();
      await platform.captureException(error: StateError('blocked'));
      await platform.optIn();
      await platform.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      expect(server.eventNames, ['sentinel event']);
      expect(callbackEvents, ['sentinel event']);
    });

    test('runs the hook once when it renames an exception event', () async {
      final server = await LocalPostHogServer.start();
      var callbackCount = 0;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            callbackCount++;
            event.event = 'renamed exception';
            event.userProperties = {'source': 'exception hook'};
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.captureException(error: StateError('renamed'));

      final event = await server.waitForEvent('renamed exception');
      expect(callbackCount, 1);
      expect(_propertiesOf(event)[r'$set'], {'source': 'exception hook'});
    });
  });

  group('Error autocapture', () {
    test('reports PlatformDispatcher errors through the desktop client',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));
      final previousOnError = PlatformDispatcher.instance.onError;
      addTearDown(() => PlatformDispatcher.instance.onError = previousOnError);
      addTearDown(PostHogErrorTrackingAutoCaptureIntegration.uninstall);

      PostHogErrorTrackingAutoCaptureIntegration.install(
        config: PostHogErrorTrackingConfig()
          ..capturePlatformDispatcherErrors = true,
        posthog: platform,
      );
      PlatformDispatcher.instance.onError!(
        StateError('uncaught'),
        StackTrace.current,
      );

      final event = await server.waitForEvent(r'$exception');
      final exceptionList = _propertiesOf(event)[r'$exception_list']! as List;
      final exception = Map<String, Object?>.from(exceptionList.first as Map);
      expect(exception['value'], 'Bad state: uncaught');
      expect((exception['mechanism']! as Map)['type'], 'PlatformDispatcher');
    });
  });

  group('Exception steps', () {
    List<Object?>? stepMessagesOf(Map<String, Object?> event) {
      final steps = _propertiesOf(event)[r'$exception_steps'] as List?;
      return steps?.map((step) => (step as Map)[r'$message']).toList();
    }

    List<Map<String, Object?>> exceptionsOn(LocalPostHogServer server) =>
        server.events
            .where((event) => event['event'] == r'$exception')
            .toList();

    Object? errorOf(Map<String, Object?> event) =>
        ((_propertiesOf(event)[r'$exception_list']! as List).first
            as Map)['value'];

    test(r'attach to every $exception in the order recorded', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.addExceptionStep('first', properties: {'screen': 'cart'});
      await platform.addExceptionStep('second');
      await platform.captureException(error: StateError('one'));
      await platform.addExceptionStep('third');
      await platform.captureException(error: StateError('two'));
      await platform.capture(eventName: 'sentinel event');

      final sentinel = await server.waitForEvent('sentinel event');
      final exceptions = exceptionsOn(server);
      expect(stepMessagesOf(exceptions[0]), ['first', 'second']);
      expect(stepMessagesOf(exceptions[1]), ['first', 'second', 'third']);
      final firstStep = (_propertiesOf(exceptions[0])[r'$exception_steps']!
          as List)[0] as Map;
      expect(firstStep['screen'], 'cart');
      expect(firstStep[r'$timestamp'], isA<String>());
      expect(stepMessagesOf(sentinel), isNull);
    });

    test('normalize non-finite step and event properties identically',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      final input = {
        'ratio': double.nan,
        'finite': 42.5,
        'literal': 'NaN',
      };
      await platform.addExceptionStep('step', properties: input);
      await platform.captureException(
        error: StateError('not a number'),
        properties: input,
      );

      final properties =
          _propertiesOf(await server.waitForEvent(r'$exception'));
      final step = (properties[r'$exception_steps']! as List).single as Map;
      expect(properties, isNot(contains('ratio')));
      expect(step, isNot(contains('ratio')));
      for (final sent in [properties, step]) {
        expect(sent['finite'], 42.5);
        expect(sent['literal'], 'NaN');
      }
    });

    test(r'attach to an $exception captured by name', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.addExceptionStep('recorded');
      await platform.capture(
        eventName: r'$exception',
        properties: {
          r'$exception_list': [
            {'type': 'CustomError', 'value': 'captured by name'},
          ],
        },
      );

      final event = await server.waitForEvent(r'$exception');
      expect(stepMessagesOf(event), ['recorded']);
    });

    test(r'leave an $exception_steps set on the event unchanged', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.addExceptionStep('recorded');
      await platform.captureException(
        error: StateError('custom steps'),
        properties: {
          r'$exception_steps': [
            {r'$message': 'custom'},
          ],
        },
      );

      final event = await server.waitForEvent(r'$exception');
      expect(stepMessagesOf(event), ['custom']);
    });

    test('are visible to beforeSend, which can remove them', () async {
      final server = await LocalPostHogServer.start();
      final seen = <Object?>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seen.add(event.properties?.remove(r'$exception_steps'));
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.addExceptionStep('recorded');
      await platform.captureException(error: StateError('removed steps'));

      final event = await server.waitForEvent(r'$exception');
      expect(seen, [
        [
          {r'$message': 'recorded', r'$timestamp': isA<String>()},
        ],
      ]);
      expect(stepMessagesOf(event), isNull);
    });

    test('are not attached while disabled', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..errorTrackingConfig.exceptionSteps.enabled = false;
      final platform = await setUpPlatform(config);

      await platform.addExceptionStep('ignored');
      await platform.captureException(error: StateError('no steps'));

      final event = await server.waitForEvent(r'$exception');
      expect(stepMessagesOf(event), isNull);
    });

    test('are not recorded while opted out', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.optOut();
      await platform.addExceptionStep('while opted out');
      await platform.optIn();
      await platform.captureException(error: StateError('opted in'));

      final event = await server.waitForEvent(r'$exception');
      expect(stepMessagesOf(event), isNull);
    });

    test('survive reset and are cleared by close', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server);
      final platform = await setUpPlatform(config);

      await platform.addExceptionStep('before reset');
      await platform.reset();
      await platform.captureException(error: StateError('after reset'));
      await platform.close();
      await platform.setup(config);
      await platform.captureException(error: StateError('after close'));
      await platform.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      // The next client may send the first one's exception again, since
      // close() does not wait for the network, so they are told apart by
      // their error rather than their position.
      final stepsByError = {
        for (final event in exceptionsOn(server))
          errorOf(event): stepMessagesOf(event),
      };
      expect(stepsByError, {
        'Bad state: after reset': ['before reset'],
        'Bad state: after close': null,
      });
    });
  });

  group('Event options', () {
    test('are sent as they are, winning over their legacy properties',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(
        eventName: 'tour step',
        properties: {r'$product_tour_id': 'from-property'},
        options: {
          'process_person_profile': false,
          'cookieless_mode': true,
          'disable_skew_correction': true,
          'product_tour_id': 'from-option',
          'unknown_option': {'nested': 'x'},
          'unset_option': null,
        },
      );

      final event = await server.waitForEvent('tour step');
      expect(event['options'], {
        'process_person_profile': false,
        'cookieless_mode': true,
        'disable_skew_correction': true,
        'product_tour_id': 'from-option',
        'unknown_option': {'nested': 'x'},
      });
      expect(_propertiesOf(event), isNot(contains(r'$product_tour_id')));
    });

    test('a process_person_profile option applies to its event only', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(
        eventName: 'processed',
        options: {'process_person_profile': true},
      );
      await platform.capture(eventName: 'anonymous');

      final processed = await server.waitForEvent('processed');
      final anonymous = await server.waitForEvent('anonymous');
      expect(_optionsOf(processed)['process_person_profile'], isTrue);
      expect(_optionsOf(anonymous)['process_person_profile'], isFalse);
    });

    test('beforeSend can change them', () async {
      final server = await LocalPostHogServer.start();
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            event.options = {
              ...?event.options,
              'product_tour_id': 'from-hook',
            };
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.screen(
        screenName: 'Home',
        options: {'product_tour_id': 'from-call'},
      );
      await platform.captureException(
        error: StateError('boom'),
        options: {'disable_skew_correction': true},
      );

      final screen = _optionsOf(await server.waitForEvent(r'$screen'));
      final exception = _optionsOf(await server.waitForEvent(r'$exception'));
      expect(screen['product_tour_id'], 'from-hook');
      expect(exception['product_tour_id'], 'from-hook');
      expect(exception['disable_skew_correction'], isTrue);
    });

    test('reach the events identify, setPersonProperties, group and alias send',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));
      Map<String, Object?> options(String id) =>
          {'product_tour_id': id, 'cookieless_mode': false, 'custom': id};

      await platform.identify(userId: 'user-1', options: options('identify'));
      await platform.setPersonProperties(
        userPropertiesToSet: {'plan': 'pro'},
        options: options('set'),
      );
      await platform.group(
        groupType: 'company',
        groupKey: 'acme',
        options: options('group'),
      );
      await platform.alias(alias: 'alias-1', options: options('alias'));

      for (final (name, id) in [
        (r'$identify', 'identify'),
        (r'$set', 'set'),
        (r'$groupidentify', 'group'),
        (r'$create_alias', 'alias'),
      ]) {
        final options = _optionsOf(await server.waitForEvent(name));
        expect(options['product_tour_id'], id, reason: name);
        expect(options['cookieless_mode'], isFalse, reason: name);
        expect(options['custom'], id, reason: name);
      }
    });

    // Capture reads these strings and numbers as false too.
    for (final personless in <Object>[false, 'no', 'false', 'off', 0, 0.0]) {
      test(
          'a \$set with process_person_profile $personless '
          'does not mark the person properties as sent', () async {
        final server = await LocalPostHogServer.start();
        final platform = await setUpPlatform(configFor(server));
        await platform.identify(userId: 'user-1');

        await platform.setPersonProperties(
          userPropertiesToSet: {'plan': 'pro'},
          options: {'process_person_profile': personless},
        );
        await platform
            .setPersonProperties(userPropertiesToSet: {'plan': 'pro'});
        await platform
            .setPersonProperties(userPropertiesToSet: {'plan': 'pro'});
        await platform.capture(eventName: 'done');
        await server.waitForEvent('done');

        final sets = [
          for (final event in server.events)
            if (event['event'] == r'$set') _optionsOf(event),
        ];
        expect(
          [for (final set in sets) set['process_person_profile']],
          [personless, isNull],
        );
      });
    }

    for (final processPerson in <Object>[false, 'yes']) {
      test(
          'a \$set with process_person_profile $processPerson '
          'clears the dedup', () async {
        final server = await LocalPostHogServer.start();
        final platform = await setUpPlatform(configFor(server));
        await platform.identify(userId: 'user-1');

        await platform
            .setPersonProperties(userPropertiesToSet: {'plan': 'free'});
        await platform.setPersonProperties(
          userPropertiesToSet: {'plan': 'pro'},
          options: {'process_person_profile': processPerson},
        );
        await platform
            .setPersonProperties(userPropertiesToSet: {'plan': 'free'});
        await platform.capture(eventName: 'done');
        await server.waitForEvent('done');

        final plans = [
          for (final event in server.events)
            if (event['event'] == r'$set')
              ((event['properties'] as Map)[r'$set'] as Map)['plan'],
        ];
        expect(plans, ['free', 'pro', 'free']);
      });
    }
  });

  group('captureAi', () {
    test('sends to the AI endpoint through beforeSend and returns the uuid',
        () async {
      final server = await LocalPostHogServer.start();
      PostHogEvent? seen;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seen = event;
            event.properties = {...?event.properties, 'from_hook': true};
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      final uuid = await platform.captureAi(
        eventName: r'$ai_generation',
        properties: {r'$ai_model': 'gpt-5'},
        options: {'custom': 'x'},
      );
      await platform.flush();

      final event = await server.waitForAiEvent(r'$ai_generation');
      expect(uuid, isNotNull);
      expect(event['uuid'], uuid);
      expect(_propertiesOf(event)[r'$ai_model'], 'gpt-5');
      expect(_propertiesOf(event)['from_hook'], isTrue);
      expect(_optionsOf(event)['custom'], 'x');
      expect(seen!.properties, contains(r'$session_id'));
      expect(server.eventNames, isNot(contains(r'$ai_generation')));
    });

    test('returns null when beforeSend drops the event', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server)
        ..beforeSend = [
          (event) => event.event == r'$ai_generation' ? null : event,
        ]);

      final uuid = await platform.captureAi(eventName: r'$ai_generation');
      await platform.captureAi(eventName: r'$ai_span');

      expect(uuid, isNull);
      await server.waitForAiEvent(r'$ai_span');
      expect(server.aiEvents, hasLength(1));
    });

    test('returns null when the event is over captureAiMaxEventBytes',
        () async {
      final server = await LocalPostHogServer.start();
      final platform =
          await setUpPlatform(configFor(server)..captureAiMaxEventBytes = 4096);

      final uuid = await platform.captureAi(
        eventName: r'$ai_generation',
        properties: {r'$ai_input': 'x' * 5000},
      );

      expect(uuid, isNull);
    });

    test('an oversized event does not turn on person processing', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server)
        ..preloadFeatureFlags = false
        ..captureAiMaxEventBytes = 4096);

      final uuid = await platform.captureAi(
        eventName: r'$ai_generation',
        properties: {r'$ai_input': 'x' * 5000},
        userProperties: {'email': 'user@example.com'},
      );
      await platform.capture(eventName: 'after drop');
      await platform.reloadFeatureFlags();

      expect(uuid, isNull);
      final event = await server.waitForEvent('after drop');
      expect(_optionsOf(event)['process_person_profile'], isFalse);
      expect(server.flagsRequests.single.body['person_properties'],
          isNot(contains('email')));
    });

    test('returns null while opted out', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));
      await platform.optOut();

      expect(await platform.captureAi(eventName: r'$ai_generation'), isNull);
    });

    test('logs a non-AI event name and still sends it', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      final lines = await _printsOf(
          () => platform.captureAi(eventName: 'not an AI event'));

      expect(lines, [contains(r'does not start with $ai_')]);
      await platform.flush();
      expect(server.aiEvents.single['event'], 'not an AI event');
    });
  });

  group('Application lifecycle', () {
    /// A launch of the app with [build], keeping its state in [appDirectory].
    PosthogFlutterDesktop launch(
      Directory appDirectory, {
      String build = '100',
    }) =>
        createPlatform(
          appDirectory: appDirectory,
          appInfo: DesktopAppInfo(version: '1.0.0', build: build),
        );

    test('the first setup captures Application Installed', () async {
      final server = await LocalPostHogServer.start();
      await launch(createAppDirectory()).setup(configFor(server));

      final event = await server.waitForEvent('Application Installed');
      final properties = _propertiesOf(event);
      expect(properties['version'], '1.0.0');
      expect(properties['build'], 100);
      expect(properties[r'$app_version'], '1.0.0');
      expect(properties[r'$app_build'], 100);
    });

    test('a launch with a new build captures Application Updated', () async {
      final server = await LocalPostHogServer.start();
      final appDirectory = createAppDirectory();
      final firstLaunch = launch(appDirectory);
      await firstLaunch.setup(configFor(server));
      await server.waitForEvent('Application Installed');
      await firstLaunch.close();

      await launch(appDirectory, build: '101').setup(configFor(server));

      final event = await server.waitForEvent('Application Updated');
      expect(_propertiesOf(event)['previous_build'], 100);
      expect(_propertiesOf(event)['build'], 101);
    });

    test('reset keeps the recorded version for the next launch', () async {
      final server = await LocalPostHogServer.start();
      final appDirectory = createAppDirectory();
      final firstLaunch = launch(appDirectory);
      await firstLaunch.setup(configFor(server));
      await server.waitForEvent('Application Installed');

      // A logout, then the next launch of the same version.
      await firstLaunch.reset();
      await firstLaunch.close();
      final nextLaunch = launch(appDirectory);
      await nextLaunch.setup(configFor(server));
      await nextLaunch.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      final lifecycleEvents = server.events
          .where((event) => '${event['event']}'.startsWith('Application '));
      // close() does not wait for the network, so the install can be sent
      // again by the next launch; it keeps its uuid, which PostHog dedupes.
      expect(
        {for (final event in lifecycleEvents) event['event']},
        {'Application Installed'},
      );
      expect(
          {for (final event in lifecycleEvents) event['uuid']}, hasLength(1));
    });

    test('an app whose build recorded no version captures no install',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(eventName: 'sentinel event');

      final sentinel = await server.waitForEvent('sentinel event');
      expect(server.eventNames, ['sentinel event']);
      expect(_propertiesOf(sentinel), isNot(contains(r'$app_version')));
    });

    test('lifecycle events bypass the beforeSend callbacks', () async {
      final server = await LocalPostHogServer.start();
      final seenEventNames = <String>[];
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seenEventNames.add(event.event);
            return event;
          },
        ];
      await launch(createAppDirectory()).setup(config);

      await server.waitForEvent('Application Installed');
      expect(seenEventNames, isEmpty);
    });

    test('an app opted out at setup reports its install on opt-in', () async {
      final server = await LocalPostHogServer.start();
      final platform = launch(createAppDirectory());
      await platform.setup(configFor(server)..optOut = true);

      await platform.optIn();

      await server.waitForEvent('Application Installed');
    });
  });

  group('Storage', () {
    test('keeps each project in its own directory', () async {
      final server = await LocalPostHogServer.start();
      final appDirectory = createAppDirectory();

      Future<void> runWithToken(String projectToken) async {
        final platform = createPlatform(appDirectory: appDirectory);
        await platform.setup(configFor(server, projectToken: projectToken));
        // The first read persists the generated anonymous id.
        await platform.getDistinctId();
        await platform.close();
      }

      await runWithToken('token_one');
      await runWithToken('token_two');

      final sep = Platform.pathSeparator;
      expect(
        Directory('${appDirectory.path}${sep}token_one').existsSync(),
        isTrue,
      );
      expect(
        Directory('${appDirectory.path}${sep}token_two').existsSync(),
        isTrue,
      );
    });

    test('the next launch keeps the identity and the opt-out', () async {
      final server = await LocalPostHogServer.start();
      final appDirectory = createAppDirectory();
      final firstLaunch = createPlatform(appDirectory: appDirectory);
      await firstLaunch.setup(configFor(server));
      final distinctId = await firstLaunch.getDistinctId();
      await firstLaunch.optOut();
      await firstLaunch.close();

      final nextLaunch = createPlatform(appDirectory: appDirectory);
      await nextLaunch.setup(configFor(server));

      expect(await nextLaunch.isOptOut(), isTrue);
      expect(await nextLaunch.getDistinctId(), distinctId);
    });
    test('an event left unsent at close is sent once after the next setup',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond =
          (_) => const PostHogResponse(HttpStatus.serviceUnavailable);
      final platform = createPlatform();
      await platform.setup(configFor(server));
      await platform.capture(eventName: 'kept');
      await platform.close();

      // The server records the events of the refused requests too.
      final refused = server.eventNames.length;
      server.respond = (_) => const PostHogResponse(HttpStatus.ok);
      await platform.setup(configFor(server));
      await platform.capture(eventName: 'sentinel');
      await server.waitForEvent('sentinel');

      expect(server.eventNames.skip(refused).where((name) => name == 'kept'),
          hasLength(1));
    });

    test('an event sent before close is not sent again after the next setup',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = createPlatform();
      await platform.setup(configFor(server));
      await platform.capture(eventName: 'once');
      await server.waitForEvent('once');
      await platform.close();

      await platform.setup(configFor(server));
      await platform.capture(eventName: 'sentinel');
      await server.waitForEvent('sentinel');

      expect(server.eventNames.where((name) => name == 'once'), hasLength(1));
    });
  });

  group('PosthogFlutterDesktop.setup', () {
    test('waits for storage before identify and capture', () async {
      final server = await LocalPostHogServer.start();
      final directory = createAppDirectory();
      final release = Completer<String?>();
      final platform =
          createPlatform(resolveAppDirectory: () => release.future);
      final setup = platform.setup(configFor(server));
      final identify = platform.identify(userId: 'early-user');
      final capture = platform.capture(eventName: 'early event');
      var completed = false;
      capture.then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(server.events, isEmpty);

      release.complete(directory.path);
      await Future.wait([setup, identify, capture]);
      final event = await server.waitForEvent('early event');
      expect(event['distinct_id'], 'early-user');
    });

    test('disable during storage lookup applies before subsequent events',
        () async {
      final server = await LocalPostHogServer.start();
      final directory = createAppDirectory();
      final release = Completer<String?>();
      final platform =
          createPlatform(resolveAppDirectory: () => release.future);
      final setup = platform.setup(configFor(server));
      final disable = platform.optOut();
      final capture = platform.capture(eventName: 'disabled event');
      release.complete(directory.path);
      await Future.wait([setup, disable, capture]);
      expect(await platform.isOptOut(), isTrue);
      await platform.optIn();
      await platform.capture(eventName: 'enabled event');
      await server.waitForEvent('enabled event');
      expect(server.eventNames, ['enabled event']);
    });

    test('an early capture respects the opt-out restored from disk', () async {
      final server = await LocalPostHogServer.start();
      final directory = createAppDirectory();
      final previousLaunch = createPlatform(appDirectory: directory);
      await previousLaunch.setup(configFor(server));
      await previousLaunch.optOut();
      await previousLaunch.close();

      final release = Completer<String?>();
      final platform =
          createPlatform(resolveAppDirectory: () => release.future);
      final setup = platform.setup(configFor(server));
      final capture = platform.capture(eventName: 'early event');
      release.complete(directory.path);
      await Future.wait([setup, capture]);
      expect(await platform.isOptOut(), isTrue);
      await platform.optIn();
      await platform.capture(eventName: 'enabled event');
      await server.waitForEvent('enabled event');
      expect(server.eventNames, ['enabled event']);
    });

    test('overlapping setup shares storage lookup and applies latest hooks',
        () async {
      final server = await LocalPostHogServer.start();
      final otherServer = await LocalPostHogServer.start();
      final directory = createAppDirectory();
      final release = Completer<String?>();
      var lookups = 0;
      final platform = createPlatform(resolveAppDirectory: () {
        lookups++;
        return release.future;
      });
      final first = platform.setup(configFor(server));
      final second =
          platform.setup(configFor(otherServer, projectToken: 'other')
            ..beforeSend = [
              (event) => event..properties = {'hook': 'latest'}
            ]);
      release.complete(directory.path);
      await Future.wait([first, second]);
      await platform.capture(eventName: 'event');
      final event = await server.waitForEvent('event');
      expect(_propertiesOf(event)['hook'], 'latest');
      expect(otherServer.events, isEmpty);
      expect(otherServer.flagsRequests, isEmpty);
      expect(lookups, 1);
    });

    test('close cancels pending setup and waiting operations', () async {
      final server = await LocalPostHogServer.start();
      final directory = createAppDirectory();
      final release = Completer<String?>();
      final platform =
          createPlatform(resolveAppDirectory: () => release.future);
      final setup = platform.setup(configFor(server));
      final capture = platform.capture(eventName: 'cancelled event');
      await platform.close();
      release.complete(directory.path);
      await Future.wait([setup, capture]);
      expect(await platform.getDistinctId(), isEmpty);
      expect(directory.listSync(), isEmpty);
      expect(server.events, isEmpty);
      expect(server.flagsRequests, isEmpty);
    });

    test('a cancelled lookup cannot replace a new client', () async {
      final server = await LocalPostHogServer.start();
      final otherServer = await LocalPostHogServer.start();
      final release = Completer<String?>();
      final oldDirectory = createAppDirectory();
      final nextDirectory = createAppDirectory();
      var lookups = 0;
      final platform = createPlatform(resolveAppDirectory: () {
        return ++lookups == 1
            ? release.future
            : Future.value(nextDirectory.path);
      });
      final first = platform.setup(configFor(server));
      final identify = platform.identify(userId: 'cancelled-user');
      final capture = platform.capture(eventName: 'cancelled event');
      await platform.close();
      await platform.setup(configFor(otherServer, projectToken: 'other'));
      final distinctId = await platform.getDistinctId();
      release.complete(oldDirectory.path);
      await Future.wait([first, identify, capture]);
      expect(await platform.getDistinctId(), distinctId);
      await platform.capture(eventName: 'new client event');
      await otherServer.waitForEvent('new client event');
      expect(otherServer.eventNames, ['new client event']);
      expect(server.events, isEmpty);
      expect(server.flagsRequests, isEmpty);
      expect(oldDirectory.listSync(), isEmpty);
    });

    test('missing storage still creates a working memory-only client',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = createPlatform(resolveAppDirectory: () async => null);
      await platform.setup(configFor(server));
      await platform.identify(userId: 'memory-user');
      await platform.capture(eventName: 'memory event');
      final event = await server.waitForEvent('memory event');
      expect(event['distinct_id'], 'memory-user');
      await platform.close();
      await platform.setup(configFor(server));
      expect(await platform.getDistinctId(), isNot('memory-user'));
    });

    test('calls made right after an unawaited setup reach the client',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = createPlatform();

      final setup = platform.setup(configFor(server));
      final identify = platform.identify(userId: 'early-user');
      await Future.wait([setup, identify]);

      expect(await platform.getDistinctId(), 'early-user');
      final event = await server.waitForEvent(r'$identify');
      expect(event['distinct_id'], 'early-user');
    });

    test('disable right after an unawaited setup keeps the user opted out',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = createPlatform();

      final setup = platform.setup(configFor(server));
      final disable = platform.optOut();
      await Future.wait([setup, disable]);

      expect(await platform.isOptOut(), isTrue);
    });

    test('a repeated setup keeps the running client', () async {
      final server = await LocalPostHogServer.start();
      final otherServer = await LocalPostHogServer.start();
      final platform = await setUpPlatform(
        configFor(server),
      );

      await platform.setup(
        configFor(otherServer, projectToken: 'other'),
      );
      await platform.capture(eventName: 'after repeated setup');

      await server.waitForEvent('after repeated setup');
      expect(otherServer.events, isEmpty);
      expect(otherServer.flagsRequests, isEmpty);
    });

    test('a repeated setup applies its beforeSend callbacks', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(
        configFor(server)
          ..beforeSend = [
            (event) => event..properties = {'hook': 'first'},
          ],
      );

      await platform.setup(
        configFor(server)
          ..beforeSend = [
            (event) => event..properties = {'hook': 'second'},
          ],
      );
      await platform.capture(eventName: 'hooked event');

      final event = await server.waitForEvent('hooked event');
      expect(_propertiesOf(event)['hook'], 'second');
    });

    test('setup right after an unawaited close starts the next client',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = createPlatform();

      await platform.setup(configFor(server)..flushAt = 20);
      await platform.capture(eventName: 'first client event');

      final close = platform.close();
      final setup = platform.setup(configFor(server));
      final capture = platform.capture(eventName: 'second client event');
      await Future.wait([close, setup, capture]);

      await server.waitForEvent('second client event');
      expect(server.eventNames, ['first client event', 'second client event']);
    });

    test('a repeated close waits until the queue is sent', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server)..flushAt = 20);
      await platform.capture(eventName: 'queued event');
      final batch = Completer<PostHogResponse>();
      server.respond = (_) => batch.future;

      final firstClose = platform.close();
      var repeatedCloseDone = false;
      final repeatedClose =
          platform.close().then((_) => repeatedCloseDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repeatedCloseDone, isFalse);

      batch.complete(const PostHogResponse(HttpStatus.ok));
      await Future.wait([firstClose, repeatedClose]);
    });

    test('close sends the queued events', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server)..flushAt = 20);
      await platform.capture(eventName: 'queued event');

      await platform.close();

      expect(server.eventNames, ['queued event']);
    });

    test(
        'close gives up on a server that does not answer and leaves the '
        'queue to the next client', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server)..flushAt = 20);
      await platform.capture(eventName: 'queued event');
      final unanswered = Completer<PostHogResponse>();
      server.respond = (_) => unanswered.future;

      final close = platform.close();
      // Started before close completes: the next client must still find the
      // queue on disk rather than keep its state in memory.
      final setup = platform.setup(configFor(server));
      await close;
      server.respond = (_) => const PostHogResponse(HttpStatus.ok);
      await setup;
      await platform.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      expect(server.eventNames, [
        'queued event', // the request close gave up on
        'queued event',
        'sentinel event',
      ]);
    });

    final pendingCalls = <String,
        ({
      String eventName,
      Future<void> Function(PosthogFlutterDesktop) call,
    })>{
      'capture': (
        eventName: 'pending capture',
        call: (platform) => platform.capture(eventName: 'pending capture'),
      ),
      'screen': (
        eventName: r'$screen',
        call: (platform) => platform.screen(screenName: 'Pending'),
      ),
      'captureException': (
        eventName: r'$exception',
        call: (platform) =>
            platform.captureException(error: StateError('pending')),
      ),
    };

    final identityChanges =
        <String, Future<void> Function(PosthogFlutterDesktop)>{
      'identify': (platform) => platform.identify(userId: 'next-user'),
      'reset': (platform) => platform.reset(),
    };

    for (final identityChange in identityChanges.entries) {
      for (final entry in pendingCalls.entries) {
        for (final hooked in [false, true]) {
          test(
              '${entry.key} ${hooked ? 'with' : 'without'} hooks is sent before '
              'an unawaited ${identityChange.key}', () async {
            final server = await LocalPostHogServer.start();
            final platform = await setUpPlatform(
                configFor(server)..beforeSend = [if (hooked) (event) => event]);
            final distinctId = await platform.getDistinctId();

            final call = entry.value.call(platform);
            final change = identityChange.value(platform);
            await Future.wait([call, change]);
            await platform.capture(eventName: 'sentinel event');

            await server.waitForEvent('sentinel event');
            final event = server.events.singleWhere(
                (event) => event['event'] == entry.value.eventName);
            expect(event['distinct_id'], distinctId);
          });
        }
      }
    }

    test('isOptOut reports opted out after close', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(
        configFor(server),
      );
      expect(await platform.isOptOut(), isFalse);

      await platform.close();

      expect(await platform.isOptOut(), isTrue);
    });

    test('calls after close are ignored with a debug warning', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));
      await platform.close();

      final lines = await _printsOf(() async {
        await platform.capture(eventName: 'after close');
        await platform.identify(userId: 'user-1');
      });

      expect(
          lines, [contains('capture ignored'), contains('identify ignored')]);
      expect(server.events, isEmpty);
    });
  });

  group('Bootstrap', () {
    test('seeds the distinct id and feature flags before any /flags response',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(
        configFor(server)
          ..preloadFeatureFlags = false
          ..bootstrap = const PostHogBootstrapConfig(
            distinctId: 'bootstrapped-anon',
            featureFlags: {'beta': true, 'checkout': 'variant-b'},
            featureFlagPayloads: {
              'beta': {'color': 'blue'},
            },
          ),
      );

      expect(await platform.getDistinctId(), 'bootstrapped-anon');
      expect(await platform.getFeatureFlag(key: 'beta'), isTrue);
      expect(await platform.getFeatureFlag(key: 'checkout'), 'variant-b');
      expect(
        (await platform.getFeatureFlagResult(
          key: 'beta',
          sendFeatureFlagEvent: false,
        ))
            ?.payload,
        {'color': 'blue'},
      );
      expect(server.flagsRequests, isEmpty);
    });

    test('an identified bootstrap sends events as the identified user',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(
        configFor(server)
          ..preloadFeatureFlags = false
          ..bootstrap = const PostHogBootstrapConfig(
            distinctId: 'known-user',
            isIdentifiedId: true,
          ),
      );

      await platform.capture(eventName: 'after bootstrap');

      final event = await server.waitForEvent('after bootstrap');
      expect(event['distinct_id'], 'known-user');
      expect(_propertiesOf(event)[r'$is_identified'], isTrue);
    });
  });

  group('Feature flag evaluation', () {
    test('flags requests carry default person properties', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      final preload = await server.waitForFlagsRequest(0);
      final personProperties =
          Map<String, Object?>.from(preload['person_properties']! as Map);
      expect(personProperties[r'$device_type'], 'Desktop');
      expect(personProperties[r'$os_name'], isNotNull);
      expect(personProperties[r'$lib'], 'posthog-flutter');
      expect(personProperties[r'$lib_version'], postHogFlutterVersion);

      await platform.setPersonPropertiesForFlags({r'$os_name': 'Custom OS'});
      await platform.reloadFeatureFlags();

      final reload = await server.waitForFlagsRequest(1);
      final overridden =
          Map<String, Object?>.from(reload['person_properties']! as Map);
      expect(overridden[r'$os_name'], 'Custom OS');
      expect(overridden[r'$device_type'], 'Desktop');
    });

    test('setPersonProperties updates flag properties without a reload',
        () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(
        configFor(server)..preloadFeatureFlags = false,
      );

      await platform.setPersonProperties(
        userPropertiesToSet: {'plan': 'pro'},
      );
      await platform.reloadFeatureFlags();

      // Only the explicit reload reached /flags, already carrying the
      // property.
      expect(server.flagsRequests, hasLength(1));
      expect(
        Map<String, Object?>.from(
          server.flagsRequests.single.body['person_properties']! as Map,
        ),
        containsPair('plan', 'pro'),
      );
    });

    test(
        r'getFeatureFlagResult with sendFeatureFlagEvent false does not capture $feature_flag_called',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final config = configFor(server);
      final platform = await setUpPlatform(config);
      await flagsLoaded;

      final silent = await platform.getFeatureFlagResult(
        key: 'variant-flag',
        sendFeatureFlagEvent: false,
      );
      expect(silent?.payload, {'color': 'blue'});

      await platform.capture(eventName: 'sentinel event');
      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains(r'$feature_flag_called')));

      // The default evaluation path still reports the call.
      final result = await platform.getFeatureFlagResult(key: 'variant-flag');
      expect(result?.variant, 'test-variant');
      final called = await server.waitForEvent(r'$feature_flag_called');
      expect(_propertiesOf(called)[r'$feature_flag'], 'variant-flag');
    });

    test(
        'captureFeatureView and captureFeatureInteraction match the native event shape',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final config = configFor(server);
      final platform = await setUpPlatform(config);
      await flagsLoaded;

      await platform.captureFeatureView(flag: 'variant-flag');
      await platform.captureFeatureInteraction(
          flag: 'other-flag', flagVariant: 'explicit');
      await platform.captureFeatureView(flag: 'unknown-flag');
      await platform.capture(eventName: 'sentinel event');
      await server.waitForEvent('sentinel event');

      final view = _propertiesOf(await server.waitForEvent(r'$feature_view'));
      expect(view['feature_flag'], 'variant-flag');
      expect(view['feature_flag_variant'], 'test-variant');
      expect(view[r'$set'], {r'$feature_view/variant-flag': 'test-variant'});

      final interaction =
          _propertiesOf(await server.waitForEvent(r'$feature_interaction'));
      expect(interaction['feature_flag'], 'other-flag');
      expect(interaction['feature_flag_variant'], 'explicit');
      expect(interaction[r'$set'],
          {r'$feature_interaction/other-flag': 'explicit'});

      expect(server.eventNames.where((name) => name == r'$feature_view'),
          hasLength(1));
      expect(server.eventNames, isNot(contains(r'$feature_flag_called')));
    });

    test('captureFeatureView keeps the user it was called for across reset',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final config = configFor(server);
      final platform = await setUpPlatform(config);
      await flagsLoaded;
      final distinctId = await platform.getDistinctId();

      unawaited(platform.captureFeatureView(flag: 'variant-flag'));
      await platform.reset();

      final view = await server.waitForEvent(r'$feature_view');
      expect(view['distinct_id'], distinctId);
    });

    test('isFeatureEnabled defaultValue only applies to flags with no value',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json({
            'flags': {
              ..._variantFlagResponse()['flags']! as Map<String, Object?>,
              'off-flag': {'key': 'off-flag', 'enabled': false},
            },
          });
      final flagsLoaded = _firstFlagsLoad();
      final platform = await setUpPlatform(configFor(server));
      await flagsLoaded;

      expect(await platform.isFeatureEnabled('missing', defaultValue: true),
          isTrue);
      expect(await platform.isFeatureEnabled('missing', defaultValue: false),
          isFalse);
      expect(await platform.isFeatureEnabled('off-flag', defaultValue: true),
          isFalse);
      expect(
          await platform.isFeatureEnabled('variant-flag', defaultValue: false),
          isTrue);
    });

    test(r'$feature_flag_called does not report the defaultValue', () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final platform = await setUpPlatform(configFor(server));
      await flagsLoaded;

      await platform.isFeatureEnabled('missing', defaultValue: true);

      final called = await server.waitForEvent(r'$feature_flag_called');
      expect(_propertiesOf(called)[r'$feature_flag_response'], isNull);
    });

    test(
        'isFeatureEnabled returns the defaultValue after a failed flags request',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => const PostHogResponse(500);
      final platform = await setUpPlatform(configFor(server));
      await platform.reloadFeatureFlags();

      expect(await platform.isFeatureEnabled('missing', defaultValue: true),
          isTrue);
    });

    test(r'sendFeatureFlagEvent false skips $feature_flag_called', () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final config = configFor(server);
      final platform = await setUpPlatform(config);
      await flagsLoaded;

      expect(
          await platform.isFeatureEnabled('variant-flag',
              sendFeatureFlagEvent: false),
          isTrue);
      expect(
          await platform.getFeatureFlag(
              key: 'variant-flag', sendFeatureFlagEvent: false),
          'test-variant');
      await platform.capture(eventName: 'sentinel event');
      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains(r'$feature_flag_called')));
    });

    test(
        r'getFeatureFlag follows config.sendFeatureFlagEvent unless overridden',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final config = configFor(server)..sendFeatureFlagEvent = false;
      final platform = await setUpPlatform(config);
      await flagsLoaded;

      expect(
          await platform.getFeatureFlag(key: 'variant-flag'), 'test-variant');
      await platform.capture(eventName: 'sentinel event');
      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains(r'$feature_flag_called')));

      await platform.getFeatureFlag(
          key: 'variant-flag', sendFeatureFlagEvent: true);
      final called = await server.waitForEvent(r'$feature_flag_called');
      expect(_propertiesOf(called)[r'$feature_flag'], 'variant-flag');
    });

    test(
        r'getAllFeatureFlags returns every loaded flag without capturing $feature_flag_called',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags({
        'flags': {
          ..._variantFlagResponse()['flags']! as Map,
          'off-flag': {'key': 'off-flag', 'enabled': false},
        },
      });
      final platform = await setUpPlatform(
        configFor(server)..preloadFeatureFlags = false,
      );

      expect(await platform.getAllFeatureFlags(), isNull);

      await platform.reloadFeatureFlags();
      final flags = await platform.getAllFeatureFlags();
      expect(
          flags,
          unorderedEquals([
            const PostHogFeatureFlagResult(
                key: 'variant-flag', enabled: true, variant: 'test-variant'),
            const PostHogFeatureFlagResult(key: 'off-flag', enabled: false),
          ]));
      expect(flags!.firstWhere((flag) => flag.key == 'variant-flag').payload,
          {'color': 'blue'});

      await platform.capture(eventName: 'sentinel event');
      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains(r'$feature_flag_called')));
    });

    test(
        'reloadFeatureFlags returns the loaded flags, and the last known ones when loading fails',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final announced = <PostHogFeatureFlagsLoaded>[];
      final subscription = FeatureFlagsListeners.instance.add(announced.add);
      addTearDown(subscription.unsubscribe);
      final platform =
          await setUpPlatform(configFor(server)..preloadFeatureFlags = false);

      final loaded = await platform.reloadFeatureFlags();
      expect(loaded.variants, {'variant-flag': 'test-variant'});
      expect(loaded.errorsLoading, isFalse);

      server.respond = (_) => const PostHogResponse(HttpStatus.badRequest);
      final failed = await platform.reloadFeatureFlags();
      expect(failed.variants, {'variant-flag': 'test-variant'});
      expect(failed.errorsLoading, isTrue);
      expect(announced.last.errorsLoading, isTrue);
    });

    test(
        r'getFeatureFlagResult follows config.sendFeatureFlagEvent unless overridden',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final flagsLoaded = _firstFlagsLoad();
      final config = configFor(server)..sendFeatureFlagEvent = false;
      final platform = await setUpPlatform(config);
      await flagsLoaded;

      expect(
          (await platform.getFeatureFlagResult(key: 'variant-flag'))?.variant,
          'test-variant');
      await platform.capture(eventName: 'sentinel event');
      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains(r'$feature_flag_called')));

      await platform.getFeatureFlagResult(
          key: 'variant-flag', sendFeatureFlagEvent: true);
      final called = await server.waitForEvent(r'$feature_flag_called');
      expect(_propertiesOf(called)[r'$feature_flag'], 'variant-flag');
    });

    test(
        'reloadFeatureFlags returns the loaded flags, and the last known ones when loading fails',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json(_variantFlagResponse());
      final announced = <PostHogFeatureFlagsLoaded>[];
      final subscription = FeatureFlagsListeners.instance.add(announced.add);
      addTearDown(subscription.unsubscribe);
      final platform =
          await setUpPlatform(configFor(server)..preloadFeatureFlags = false);

      final loaded = await platform.reloadFeatureFlags();
      expect(loaded.variants, {'variant-flag': 'test-variant'});
      expect(loaded.errorsLoading, isFalse);

      server.respond = (_) => const PostHogResponse(HttpStatus.badRequest);
      final failed = await platform.reloadFeatureFlags();
      expect(failed.variants, {'variant-flag': 'test-variant'});
      expect(failed.errorsLoading, isTrue);
      expect(announced.last.errorsLoading, isTrue);
    });

    test('onFeatureFlags listeners receive each load', () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json(_variantFlagResponse());
      final received = <PostHogFeatureFlagsLoaded>[];
      final subscription = FeatureFlagsListeners.instance.add(received.add);
      addTearDown(subscription.unsubscribe);
      final platform =
          await setUpPlatform(configFor(server)..preloadFeatureFlags = false);

      await platform.reloadFeatureFlags();

      expect(received.last.variants, {'variant-flag': 'test-variant'});
    });

    test('a reset started by a listener is not undone by the load', () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json(_variantFlagResponse());
      FeatureFlagsListeners.instance.clear();
      // What reset() and close() do before reaching the platform.
      final starter = FeatureFlagsListeners.instance
          .add((_) => FeatureFlagsListeners.instance.clear());
      addTearDown(starter.unsubscribe);
      final platform =
          await setUpPlatform(configFor(server)..preloadFeatureFlags = false);

      await platform.reloadFeatureFlags();
      final received = <PostHogFeatureFlagsLoaded>[];
      final subscription = FeatureFlagsListeners.instance.add(received.add);
      addTearDown(subscription.unsubscribe);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test('onFeatureFlags reports the flags cached by the previous launch',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = _answerFlags(_variantFlagResponse());
      final appDirectory = createAppDirectory();
      final previousLaunch = createPlatform(appDirectory: appDirectory);
      await previousLaunch
          .setup(configFor(server)..preloadFeatureFlags = false);
      await previousLaunch.reloadFeatureFlags();
      await previousLaunch.close();

      final platform = createPlatform(appDirectory: appDirectory);
      final payloads = <Future<Object?>>[];
      final announced = Completer<void>();
      final subscription = FeatureFlagsListeners.instance.add((_) {
        payloads.add(platform
            .getFeatureFlagResult(
                key: 'variant-flag', sendFeatureFlagEvent: false)
            .then((result) => result?.payload));
        if (!announced.isCompleted) announced.complete();
      });
      addTearDown(subscription.unsubscribe);
      await platform.setup(configFor(server)..preloadFeatureFlags = false);
      await announced.future;

      expect(await Future.wait(payloads), [
        {'color': 'blue'},
      ]);
      expect(server.flagsRequests, hasLength(1),
          reason: 'the cached flags need no request of their own');
    });
  });
}

Future<void> _firstFlagsLoad() {
  FeatureFlagsListeners.instance.clear();
  final loaded = Completer<void>();
  final subscription = FeatureFlagsListeners.instance.add((_) {
    if (!loaded.isCompleted) loaded.complete();
  });
  addTearDown(subscription.unsubscribe);
  return loaded.future;
}

Map<String, Object?> _propertiesOf(Map<String, Object?> event) =>
    Map<String, Object?>.from(event['properties']! as Map);

Map<String, Object?> _optionsOf(Map<String, Object?> event) =>
    Map<String, Object?>.from((event['options'] ?? const {}) as Map);

/// Runs [body] and returns the lines it printed.
Future<List<String>> _printsOf(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

/// A /flags/ v2 response with one multivariate flag carrying a payload.
Map<String, Object?> _variantFlagResponse() => {
      'flags': {
        'variant-flag': {
          'key': 'variant-flag',
          'enabled': true,
          'variant': 'test-variant',
          'metadata': {
            'id': 1,
            'version': 2,
            'payload': '{"color":"blue"}',
          },
        },
      },
    };

class _LateFailingDeletes extends GatedWorker {
  final gate = Completer<void>();
  var fail = true;

  @override
  Future<List<String>> delete(List<String> paths) => fail
      ? gate.future.then((_) => throw StateError('job failed'))
      : super.delete(paths);
}

/// Answers `/flags/` with [flags], and every other request with a success.
PostHogResponder _answerFlags(Map<String, Object?> flags) =>
    (request) => request.isFlags
        ? PostHogResponse.json(flags)
        : const PostHogResponse(HttpStatus.ok);
