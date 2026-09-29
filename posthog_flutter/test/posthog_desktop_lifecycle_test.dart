import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_desktop_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storageDir;
  late List<({String event, Map<String, Object>? properties})> captured;
  late int flushes;

  // The message the Windows and Linux embedders send when window focus or
  // visibility changes; the binding expands it into single-step transitions.
  Future<void> moveApp(AppLifecycleState state) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        SystemChannels.lifecycle.name,
        SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
        (_) {},
      );

  setUp(() async {
    storageDir = Directory.systemTemp.createTempSync('posthog_lifecycle');
    addTearDown(() => storageDir.deleteSync(recursive: true));
    captured = [];
    flushes = 0;
    // Every test starts with the window visible but not focused.
    await moveApp(AppLifecycleState.inactive);
  });

  DesktopAppLifecycle createLifecycle({
    String? version = '1.0.0',
    String? build = '100',
    bool captureEvents = true,
    bool withBinding = true,
  }) {
    final lifecycle = DesktopAppLifecycle(
      binding: withBinding ? WidgetsBinding.instance : null,
      storageDirectory: storageDir.path,
      version: version,
      build: build,
      captureEvents: captureEvents,
      capture: (event, properties) =>
          captured.add((event: event, properties: properties)),
      flush: () async => flushes++,
    );
    addTearDown(lifecycle.dispose);
    return lifecycle;
  }

  /// Starts a lifecycle for a previous launch of the app, then forgets what
  /// it captured.
  void launchPreviously({String? version = '1.0.0', String? build = '100'}) {
    createLifecycle(version: version, build: build)
      ..start()
      ..dispose();
    captured.clear();
  }

  List<String> eventNames() => [for (final call in captured) call.event];

  Map<String, Object>? propertiesOf(String event) =>
      captured.firstWhere((call) => call.event == event).properties;

  group('install and update', () {
    test('the first launch captures Application Installed', () {
      createLifecycle().start();

      expect(eventNames(), ['Application Installed']);
      expect(propertiesOf('Application Installed'), {
        'version': '1.0.0',
        'build': 100,
      });
    });

    test('a new build captures Application Updated', () {
      launchPreviously();

      createLifecycle(version: '1.1.0', build: '110').start();

      expect(eventNames(), ['Application Updated']);
      expect(propertiesOf('Application Updated'), {
        'version': '1.1.0',
        'build': 110,
        'previous_version': '1.0.0',
        'previous_build': 100,
      });
    });

    test('the same build captures nothing, even with a new version', () {
      launchPreviously();

      createLifecycle(version: '1.0.1').start();

      expect(captured, isEmpty);
    });

    test('without a build the version is compared', () {
      launchPreviously(build: null);

      createLifecycle(version: '1.1.0', build: null).start();

      expect(eventNames(), ['Application Updated']);
      expect(propertiesOf('Application Updated'), {
        'version': '1.1.0',
        'previous_version': '1.0.0',
      });
    });

    test('a build that is not a number is reported as a string', () {
      createLifecycle(build: '1.2.3').start();

      expect(propertiesOf('Application Installed')?['build'], '1.2.3');
    });

    test('without a version or build nothing is captured or recorded', () {
      createLifecycle(version: null, build: null).start();

      expect(captured, isEmpty);
      expect(storageDir.listSync(), isEmpty);
    });

    test('the version is recorded while the events are off', () {
      createLifecycle(captureEvents: false).start();

      createLifecycle().start();

      expect(captured, isEmpty);
    });

    test('a record that cannot be read is replaced without an event', () {
      File('${storageDir.path}${Platform.pathSeparator}posthog_app_version.json')
          .writeAsStringSync('not json');

      createLifecycle().start();
      expect(captured, isEmpty);

      createLifecycle(build: '101').start();
      expect(eventNames(), ['Application Updated']);
    });
  });

  group('opened and backgrounded', () {
    test('an app already active at setup is opened as a fresh launch',
        () async {
      await moveApp(AppLifecycleState.resumed);

      createLifecycle().start(captureOpenedIfActive: true);

      expect(eventNames(), ['Application Installed', 'Application Opened']);
      expect(propertiesOf('Application Opened'), {
        'from_background': false,
        'version': '1.0.0',
        'build': 100,
      });
    });

    test('an app that becomes active later is opened then', () async {
      createLifecycle().start();
      expect(eventNames(), ['Application Installed']);

      await moveApp(AppLifecycleState.resumed);

      expect(eventNames(), ['Application Installed', 'Application Opened']);
      expect(propertiesOf('Application Opened')?['from_background'], isFalse);
    });

    test('resigning active backgrounds the app once and flushes', () async {
      launchPreviously();
      await moveApp(AppLifecycleState.resumed);
      createLifecycle().start(captureOpenedIfActive: true);
      captured.clear();

      await moveApp(AppLifecycleState.inactive);
      await moveApp(AppLifecycleState.hidden);

      expect(eventNames(), ['Application Backgrounded']);
      expect(propertiesOf('Application Backgrounded'), isNull);
      expect(flushes, 1);

      await moveApp(AppLifecycleState.resumed);

      expect(eventNames(), ['Application Backgrounded', 'Application Opened']);
      expect(propertiesOf('Application Opened'), {'from_background': true});
    });

    test('events stop while stopped but the queue is still flushed', () async {
      launchPreviously();
      await moveApp(AppLifecycleState.resumed);
      final lifecycle = createLifecycle()..start();
      captured.clear();

      lifecycle.stop();
      await moveApp(AppLifecycleState.inactive);
      await moveApp(AppLifecycleState.resumed);

      expect(captured, isEmpty);
      expect(flushes, 1);
    });

    test('a restart reports the next activation as a fresh launch', () async {
      launchPreviously();
      await moveApp(AppLifecycleState.resumed);
      final lifecycle = createLifecycle()..start(captureOpenedIfActive: true);
      captured.clear();

      lifecycle
        ..stop()
        ..start();
      expect(captured, isEmpty);

      await moveApp(AppLifecycleState.inactive);
      await moveApp(AppLifecycleState.resumed);

      expect(eventNames(), ['Application Opened']);
      expect(propertiesOf('Application Opened'), {
        'from_background': false,
        'version': '1.0.0',
        'build': 100,
      });
    });

    test('with the events off only the flush happens', () async {
      await moveApp(AppLifecycleState.resumed);
      createLifecycle(captureEvents: false).start();

      await moveApp(AppLifecycleState.inactive);
      await moveApp(AppLifecycleState.resumed);

      expect(captured, isEmpty);
      expect(flushes, 1);
    });

    test('without a binding only install and update are captured', () async {
      await moveApp(AppLifecycleState.resumed);

      createLifecycle(withBinding: false).start();
      await moveApp(AppLifecycleState.inactive);

      expect(eventNames(), ['Application Installed']);
      expect(flushes, 0);
    });

    test('dispose stops listening to the app lifecycle', () async {
      createLifecycle()
        ..start()
        ..dispose();
      captured.clear();

      await moveApp(AppLifecycleState.resumed);
      await moveApp(AppLifecycleState.inactive);

      expect(captured, isEmpty);
      expect(flushes, 0);
    });
  });
}
