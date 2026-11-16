@TestOn('windows || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
// ignore: implementation_imports
import 'package:posthog_flutter/src/posthog_desktop_storage.dart';
// ignore: implementation_imports
import 'package:posthog_flutter/src/posthog_flutter_desktop.dart';
// ignore: implementation_imports
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';

/// Runs the Windows and Linux implementation inside the built example app:
/// the plugin registrant, the application support directory, the app
/// metadata of the build and the platform HTTP stack are the real ones.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  var projectCount = 0;
  String newProjectToken() =>
      'e2e_${DateTime.now().microsecondsSinceEpoch}_${projectCount++}';

  Future<_FakePostHog> startServer() async {
    final server = await _FakePostHog.start();
    addTearDown(server.close);
    return server;
  }

  Future<void> setUpPostHog(
    _FakePostHog server,
    String projectToken, {
    int flushAt = 1,
  }) async {
    final config = PostHogConfig(projectToken)
      ..host = server.url
      ..flushAt = flushAt
      ..debug = true;
    await Posthog().setup(config);
    addTearDown(Posthog().close);
  }

  testWidgets('the plugin registrant installs the desktop implementation', (
    _,
  ) async {
    expect(
      PosthogFlutterPlatformInterface.instance,
      isA<PosthogFlutterDesktop>(),
    );
  });

  testWidgets(
    'events carry the app and OS context and the state is stored in the '
    'application support directory',
    (_) async {
      final server = await startServer();
      final projectToken = newProjectToken();
      await setUpPostHog(server, projectToken);

      await Posthog().capture(
        eventName: 'e2e event',
        properties: {'source': 'integration test'},
      );

      final event = await server.waitForEvent('e2e event');
      final properties = event['properties'] as Map<String, Object?>;
      expect(properties['source'], 'integration test');
      expect(properties[r'$lib'], 'posthog-flutter');
      expect(properties[r'$os_name'], Platform.isWindows ? 'Windows' : 'Linux');
      expect(properties[r'$os_version'], allOf(isA<String>(), isNotEmpty));
      expect(properties[r'$device_type'], 'Desktop');
      expect(properties[r'$app_name'], 'posthog_flutter_example');
      expect(properties[r'$app_version'], '1.0.0');
      expect(properties[r'$app_build'], 1);

      final appDirectory = await DesktopStorage.appDirectory();
      expect(appDirectory, isNotNull);
      expect(
        Directory(
          DesktopStorage.projectDirectory(appDirectory!, projectToken),
        ).existsSync(),
        isTrue,
      );
    },
  );

  testWidgets('flag requests carry the app and OS person properties', (
    _,
  ) async {
    final server = await startServer();
    await setUpPostHog(server, newProjectToken());

    await Posthog().reloadFeatureFlags();

    final request = await server.waitForFlagsRequest();
    final personProperties =
        request['person_properties'] as Map<String, Object?>;
    expect(personProperties[r'$app_version'], '1.0.0');
    expect(personProperties[r'$app_build'], 1);
    expect(
      personProperties[r'$os_name'],
      Platform.isWindows ? 'Windows' : 'Linux',
    );
    expect(personProperties[r'$os_version'], isNotNull);
    expect(personProperties[r'$device_type'], 'Desktop');
    expect(personProperties[r'$lib'], 'posthog-flutter');
    expect(await Posthog().getFeatureFlag('e2e-flag'), 'test-variant');
  });

  testWidgets('close sends the queued events', (_) async {
    final server = await startServer();
    await setUpPostHog(server, newProjectToken(), flushAt: 20);
    await Posthog().capture(eventName: 'queued event');

    await Posthog().close();

    expect(server.eventNames, contains('queued event'));
  });

  testWidgets('a queued event survives the client and goes out with the next', (
    _,
  ) async {
    final server = await startServer();
    final projectToken = newProjectToken();
    server.batchStatus = HttpStatus.serviceUnavailable;
    await setUpPostHog(server, projectToken, flushAt: 20);
    await Posthog().capture(eventName: 'survivor event');
    await Posthog().close();
    expect(server.eventNames, isNot(contains('survivor event')));

    server.batchStatus = HttpStatus.ok;
    await setUpPostHog(server, projectToken, flushAt: 20);
    await Posthog().flush();

    expect(server.eventNames, contains('survivor event'));
  });
}

/// A PostHog API on the loopback interface that records the batches and
/// answers every flag request with one variant flag.
class _FakePostHog {
  _FakePostHog._(this._server);

  final HttpServer _server;
  final _batches = <Map<String, Object?>>[];
  final _flagsRequests = <Map<String, Object?>>[];

  /// The status of the answers to batches.
  int batchStatus = HttpStatus.ok;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_FakePostHog> start() async {
    final server = _FakePostHog._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._serve);
    return server;
  }

  Future<void> close() => _server.close(force: true);

  List<Map<String, Object?>> get events => [
    for (final batch in _batches)
      for (final event in batch['batch'] as List<Object?>)
        event as Map<String, Object?>,
  ];

  List<Object?> get eventNames => [for (final e in events) e['event']];

  Future<Map<String, Object?>> waitForEvent(String name) async {
    await _waitFor(() => eventNames.contains(name));
    return events.firstWhere((event) => event['event'] == name);
  }

  Future<Map<String, Object?>> waitForFlagsRequest() async {
    await _waitFor(() => _flagsRequests.isNotEmpty);
    return _flagsRequests.first;
  }

  Future<void> _waitFor(bool Function() isReady) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!isReady()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('PostHog received ${eventNames.length} events: $eventNames');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final bytes = await request.fold<List<int>>([], (all, c) => all..addAll(c));
    final gzipped =
        request.headers.value(HttpHeaders.contentEncodingHeader) == 'gzip';
    final body =
        jsonDecode(utf8.decode(gzipped ? gzip.decode(bytes) : bytes))
            as Map<String, Object?>;

    final response = request.response;
    switch (request.uri.path) {
      case '/batch/':
        response.statusCode = batchStatus;
        if (batchStatus == HttpStatus.ok) _batches.add(body);
      case '/flags/':
        _flagsRequests.add(body);
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'flags': {
              'e2e-flag': {
                'key': 'e2e-flag',
                'enabled': true,
                'variant': 'test-variant',
                'metadata': {'id': 1, 'version': 1},
              },
            },
          }),
        );
      default:
        response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }
}
