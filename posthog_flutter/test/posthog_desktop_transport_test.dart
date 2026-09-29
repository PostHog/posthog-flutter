import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_desktop_app_info.dart';
import 'package:posthog_flutter/src/posthog_flutter_desktop.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import 'posthog_api_fake.dart';

class _DesktopTransportBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {}

void main() {
  _DesktopTransportBinding();

  late Directory appDirectory;
  late LocalPostHogServer server;
  late PosthogFlutterPlatformInterface previousPlatform;

  setUp(() async {
    appDirectory = Directory.systemTemp.createTempSync('posthog_transport');
    server = await LocalPostHogServer.start();
    previousPlatform = PosthogFlutterPlatformInterface.instance;
    PosthogFlutterPlatformInterface.instance = PosthogFlutterDesktop(
      appDirectory: appDirectory.path,
      appInfo: const DesktopAppInfo(
        name: 'transport_test',
        version: '1.2.3',
        build: '42',
      ),
      timezone: 'Europe/Berlin',
    );
  });

  tearDown(() async {
    await Posthog().close();
    PosthogFlutterPlatformInterface.instance = previousPlatform;
    if (appDirectory.existsSync()) appDirectory.deleteSync(recursive: true);
  });

  PostHogConfig config({int flushAt = 1}) => PostHogConfig('phc_transport')
    ..host = server.url
    ..flushAt = flushAt
    ..flushInterval = const Duration(hours: 1)
    ..captureApplicationLifecycleEvents = false;

  test('facade captures and honors consent without filesystem access',
      () async {
    PosthogFlutterPlatformInterface.instance = PosthogFlutterDesktop(
      appDirectory: null,
      appInfo: const DesktopAppInfo(name: 'memory_test'),
      timezone: null,
    );
    await IOOverrides.runZoned(() async {
      await Posthog().setup(config()..preloadFeatureFlags = false);
      await Posthog().disable();
      expect(await Posthog().isOptOut(), isTrue);
      await Posthog().capture(eventName: 'blocked event');
      await Posthog().enable();
      await Posthog().capture(eventName: 'memory event');
      await Posthog().flush();
      expect(server.eventNames, ['memory event']);
    },
        createFile: (_) => throw StateError('Unexpected file access'),
        createDirectory: (_) =>
            throw StateError('Unexpected directory access'));
  });

  test('facade sends a gzipped batch with envelope and event metadata',
      () async {
    await Posthog().setup(config(flushAt: 2)..preloadFeatureFlags = false);

    await Posthog().capture(
      eventName: 'first event',
      properties: {'source': 'desktop'},
    );
    await Posthog().capture(eventName: 'second event');
    await server.waitForEvent('second event');

    final request = server.batchRequests.single;
    expect(request.headers['content-encoding'], 'gzip');
    expect(request.headers['content-type'], 'application/json');
    expect(request.body['api_key'], 'phc_transport');
    expect(DateTime.tryParse(request.body['sent_at']! as String), isNotNull);
    expect(request.eventNames, ['first event', 'second event']);

    for (final event in request.events) {
      expect(event['uuid'], isA<String>());
      expect(DateTime.tryParse(event['timestamp']! as String), isNotNull);
      expect(event['distinct_id'], isA<String>());
      final properties = Map<String, Object?>.from(event['properties']! as Map);
      expect(properties[r'$lib'], postHogFlutterSdkName);
      expect(properties[r'$device_type'], 'Desktop');
      expect(properties[r'$app_version'], '1.2.3');
      expect(properties[r'$app_build'], 42);
      expect(properties[r'$timezone'], 'Europe/Berlin');
    }
  });

  test('facade sends flag context and blocks capture while opted out',
      () async {
    server.respond = (request) => request.isFlags
        ? PostHogResponse.json({'flags': <String, Object?>{}})
        : const PostHogResponse(HttpStatus.ok);
    await Posthog().setup(config());

    final flags = await server.waitForFlagsRequest(0);
    final personProperties =
        Map<String, Object?>.from(flags['person_properties']! as Map);
    expect(flags['token'], 'phc_transport');
    expect(personProperties[r'$lib'], postHogFlutterSdkName);
    expect(personProperties[r'$lib_version'], postHogFlutterVersion);
    expect(personProperties[r'$device_type'], 'Desktop');
    expect(personProperties[r'$app_version'], '1.2.3');

    await Posthog().disable();
    expect(await Posthog().isOptOut(), isTrue);
    await Posthog().capture(eventName: 'blocked event');
    await Posthog().enable();
    await Posthog().capture(eventName: 'allowed event');
    await server.waitForEvent('allowed event');

    expect(server.eventNames, isNot(contains('blocked event')));
    expect(server.eventNames, contains('allowed event'));
  });
}
