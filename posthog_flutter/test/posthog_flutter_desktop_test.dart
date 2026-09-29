import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_desktop_app_info.dart';
import 'package:posthog_flutter/src/posthog_flutter_desktop.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import 'posthog_api_fake.dart';

// No TestWidgetsFlutterBinding here: the test binding replaces dart:io's
// HttpClient with a stub that answers 400 to everything, and these tests
// exercise the real HTTP path against a local server.
void main() {
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
    DesktopAppInfo appInfo = const DesktopAppInfo(),
    String? timezone,
  }) {
    final platform = PosthogFlutterDesktop(
      appDirectory: (appDirectory ?? createAppDirectory()).path,
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
      'getFeatureFlagPayload': (platform) =>
          platform.getFeatureFlagPayload(key: 'flag'),
      'getFeatureFlagResult': (platform) =>
          platform.getFeatureFlagResult(key: 'flag'),
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

    test('isOptOut reports opted out', () async {
      expect(await platform.isOptOut(), isTrue);
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

    test(r'reports the platform language as $locale', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform.capture(eventName: 'localized event');

      final event = await server.waitForEvent('localized event');
      expect(
        _propertiesOf(event)[r'$locale'],
        PlatformDispatcher.instance.locale.languageCode,
      );
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

    test(r'reports $recording_status disabled on every event', () async {
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
      expect(_propertiesOf(captured)[r'$recording_status'], 'disabled');
    });
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

      await platform.disable();
      await platform.screen(screenName: 'Hidden');
      await platform.enable();
      await platform.capture(eventName: 'sentinel event');

      final event = await server.waitForEvent('sentinel event');
      expect(server.eventNames, ['sentinel event']);
      expect(seenEventNames, ['sentinel event'],
          reason: 'no callback runs for a screen while opted out');
      expect(_propertiesOf(event), isNot(contains(r'$screen_name')),
          reason: 'the screen did not become the current one');
    });

    test('keeps the screen name when a callback rebuilds the properties',
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

      final event = await server.waitForEvent(r'$screen');
      final properties = _propertiesOf(event);
      expect(properties[r'$screen_name'], 'Home Screen',
          reason: 'the screen name is re-added after the callbacks, so one '
              'dropping the key must not lose it');
      expect(properties['scrubbed'], isTrue);
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

    test('callbacks see user-provided properties only', () async {
      final server = await LocalPostHogServer.start();
      Map<String, Object>? seenProperties;
      final config = configFor(server)
        ..beforeSend = [
          (event) {
            seenProperties = event.properties;
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      await platform.capture(
        eventName: 'context event',
        properties: {'plan': 'pro'},
      );

      final event = await server.waitForEvent('context event');
      // The whole map: no $session_id, $lib or other SDK enrichment is
      // visible to the hook...
      expect(seenProperties, {'plan': 'pro'});
      // ...while the delivered event is still enriched after the hook ran.
      final properties = _propertiesOf(event);
      expect(properties, containsPair(r'$lib', 'posthog-flutter'));
      expect(properties.keys, contains(r'$session_id'));
    });

    test('SDK-internal events bypass the callbacks', () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json(_variantFlagResponse());
      final flagsLoaded = Completer<void>();
      final seenEventNames = <String>[];
      final config = configFor(server)
        ..onFeatureFlags = () {
          if (!flagsLoaded.isCompleted) flagsLoaded.complete();
        }
        ..beforeSend = [
          (event) {
            seenEventNames.add(event.event);
            return event;
          },
        ];
      final platform = await setUpPlatform(config);
      await flagsLoaded.future;

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

    test('send their values as event properties send them', () async {
      final server = await LocalPostHogServer.start();
      final platform = await setUpPlatform(configFor(server));

      await platform
          .addExceptionStep('step', properties: {'ratio': double.nan});
      await platform.captureException(
        error: StateError('not a number'),
        properties: {'ratio': double.nan},
      );

      final properties =
          _propertiesOf(await server.waitForEvent(r'$exception'));
      final step = (properties[r'$exception_steps']! as List).single as Map;
      expect(properties['ratio'], 'NaN');
      expect(step['ratio'], 'NaN');
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

      await platform.disable();
      await platform.addExceptionStep('while opted out');
      await platform.enable();
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

      await platform.enable();

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
      await firstLaunch.disable();
      await firstLaunch.close();

      final nextLaunch = createPlatform(appDirectory: appDirectory);
      await nextLaunch.setup(configFor(server));

      expect(await nextLaunch.isOptOut(), isTrue);
      expect(await nextLaunch.getDistinctId(), distinctId);
    });
  });

  group('PosthogFlutterDesktop.setup', () {
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
      final disable = platform.disable();
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

      // The closed client leaves its queued event on disk, where the next
      // client picks it up.
      final close = platform.close();
      final setup = platform.setup(configFor(server));
      final capture = platform.capture(eventName: 'second client event');
      await Future.wait([close, setup, capture]);

      await server.waitForEvent('second client event');
      expect(server.eventNames, ['first client event', 'second client event']);
    });

    test('an event whose callbacks finish after close reaches the next client',
        () async {
      final server = await LocalPostHogServer.start();
      final release = Completer<void>();
      final config = configFor(server)
        ..beforeSend = [
          (event) async {
            if (event.event == 'slow event') await release.future;
            return event;
          },
        ];
      final platform = await setUpPlatform(config);

      final slowCapture = platform.capture(eventName: 'slow event');
      await platform.close();
      await platform.setup(config);
      release.complete();
      await slowCapture;
      await platform.capture(eventName: 'sentinel event');

      await server.waitForEvent('sentinel event');
      expect(server.eventNames, ['slow event', 'sentinel event']);
    });

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
        await platform.getFeatureFlagPayload(key: 'beta'),
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

    test(r'getFeatureFlagPayload does not capture $feature_flag_called',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json(_variantFlagResponse());
      final flagsLoaded = Completer<void>();
      final config = configFor(server)
        ..onFeatureFlags = () {
          if (!flagsLoaded.isCompleted) flagsLoaded.complete();
        };
      final platform = await setUpPlatform(config);
      await flagsLoaded.future;

      final payload = await platform.getFeatureFlagPayload(
        key: 'variant-flag',
      );
      expect(payload, {'color': 'blue'});

      await platform.capture(eventName: 'sentinel event');
      await server.waitForEvent('sentinel event');
      expect(server.eventNames, isNot(contains(r'$feature_flag_called')));

      // The default evaluation path still reports the call.
      final result = await platform.getFeatureFlagResult(key: 'variant-flag');
      expect(result?.variant, 'test-variant');
      final called = await server.waitForEvent(r'$feature_flag_called');
      expect(_propertiesOf(called)[r'$feature_flag'], 'variant-flag');
    });

    test('onFeatureFlags reports the flags cached by the previous launch',
        () async {
      final server = await LocalPostHogServer.start();
      server.respond = (_) => PostHogResponse.json(_variantFlagResponse());
      final appDirectory = createAppDirectory();
      final previousLaunch = createPlatform(appDirectory: appDirectory);
      await previousLaunch
          .setup(configFor(server)..preloadFeatureFlags = false);
      await previousLaunch.reloadFeatureFlags();
      await previousLaunch.close();

      final platform = createPlatform(appDirectory: appDirectory);
      final payloads = <Future<Object?>>[];
      final announced = Completer<void>();
      await platform.setup(configFor(server)
        ..preloadFeatureFlags = false
        ..onFeatureFlags = () {
          payloads.add(platform.getFeatureFlagPayload(key: 'variant-flag'));
          if (!announced.isCompleted) announced.complete();
        });
      await announced.future;

      expect(await Future.wait(payloads), [
        {'color': 'blue'},
      ]);
      expect(server.flagsRequests, hasLength(1),
          reason: 'the cached flags need no request of their own');
    });
  });
}

Map<String, Object?> _propertiesOf(Map<String, Object?> event) =>
    Map<String, Object?>.from(event['properties']! as Map);

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
