@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/posthog_flutter_web.dart';
import 'package:posthog_flutter/src/feature_flags_listeners.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/web/web_canvas_mask_provider.dart';

/// posthog-js is initialized by the host app on web, so options the plugin
/// cannot forward must warn instead of silently doing nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(WebCanvasMaskProvider.resetForTesting);
  tearDown(WebCanvasMaskProvider.resetForTesting);

  Future<List<String>> setupCapturingLogs(PostHogConfig config) async {
    final logs = <String>[];
    await runZoned(
      () => PosthogFlutterWeb().setup(config),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => logs.add(line),
      ),
    );
    return logs;
  }

  test('warns that preloadFeatureFlags is not applied on web', () async {
    final config = PostHogConfig('test_project_token');
    config.preloadFeatureFlags = false;

    final logs = await setupCapturingLogs(config);

    final warnings =
        logs.where((line) => line.contains('preloadFeatureFlags')).toList();
    expect(warnings, hasLength(1));
    expect(warnings.single,
        contains('advanced_disable_feature_flags_on_first_load'));
  });

  test('does not warn when preloadFeatureFlags keeps its default', () async {
    final logs = await setupCapturingLogs(PostHogConfig('test_project_token'));

    expect(logs.where((line) => line.contains('preloadFeatureFlags')), isEmpty);
  });

  test('warns that bootstrap is not applied on web', () async {
    final config = PostHogConfig('test_project_token');
    config.bootstrap = PostHogBootstrapConfig(distinctId: 'user-1');

    final logs = await setupCapturingLogs(config);

    expect(logs.where((line) => line.contains('bootstrap')), hasLength(1));
  });

  test('warns that evaluationContexts is not applied on web', () async {
    final config = PostHogConfig('test_project_token');
    config.evaluationContexts = ['mobile'];

    final logs = await setupCapturingLogs(config);

    expect(logs.where((line) => line.contains('evaluationContexts')),
        hasLength(1));
  });

  test('delivers posthog-js flag loads to onFeatureFlags listeners once',
      () async {
    final listeners = <JSFunction>[];
    globalContext.setProperty(
        'posthog'.toJS,
        JSObject()
          ..setProperty(
            'onFeatureFlags'.toJS,
            ((JSFunction callback) {
              listeners.add(callback);
              return (() => listeners.remove(callback)).toJS;
            }).toJS,
          ));
    addTearDown(() => globalContext.delete('posthog'.toJS));
    final received = <PostHogFeatureFlagsLoaded>[];
    final subscription = FeatureFlagsListeners.instance.add(received.add);
    addTearDown(subscription.unsubscribe);
    final web = PosthogFlutterWeb();

    await web.setup(PostHogConfig('test_project_token'));
    await web.setup(PostHogConfig('test_project_token'));
    for (final listener in listeners.toList()) {
      listener.callAsFunction(null, ['on'].jsify(), {'on': true}.jsify(), null);
    }

    expect(received.single.variants, {'on': true});
  });

  List<JSFunction> stubPosthogJs() {
    final listeners = <JSFunction>[];
    globalContext.setProperty(
        'posthog'.toJS,
        JSObject()
          ..setProperty(
            'onFeatureFlags'.toJS,
            ((JSFunction callback) {
              listeners.add(callback);
              return (() => listeners.remove(callback)).toJS;
            }).toJS,
          ));
    addTearDown(() => globalContext.delete('posthog'.toJS));
    return listeners;
  }

  void loadFlags(List<JSFunction> listeners) {
    for (final listener in listeners.toList()) {
      listener.callAsFunction(null, ['on'].jsify(), {'on': true}.jsify(), null);
    }
  }

  group('a load arriving while reset waits behind an async beforeSend', () {
    late List<JSFunction> listeners;
    late List<String> calls;
    late Completer<void> release;
    late Future<void> resetting;

    setUp(() async {
      FeatureFlagsListeners.instance.clear();
      listeners = stubPosthogJs();
      calls = [];
      globalContext.getProperty<JSObject>('posthog'.toJS)
        ..setProperty(
          'capture'.toJS,
          ((JSString event, [JSAny? a, JSAny? b]) => calls.add('capture')).toJS,
        )
        ..setProperty('reset'.toJS, (() => calls.add('reset')).toJS);
      release = Completer<void>();
      final web = PosthogFlutterWeb();
      PosthogFlutterPlatformInterface.instance = web;
      await web.setup(PostHogConfig('test_project_token', beforeSend: [
        (event) async {
          await release.future;
          return event;
        },
      ]));

      final capturing = Posthog().capture(eventName: 'Logout clicked');
      resetting = Future.wait([capturing, Posthog().reset()]);
      await Future<void>.delayed(Duration.zero);
      loadFlags(listeners);
      expect(calls, isEmpty);
      release.complete();
      await resetting;
      expect(calls, ['capture', 'reset']);
    });

    test('is not replayed to a listener added after reset completes', () async {
      final received = <PostHogFeatureFlagsLoaded>[];
      final subscription = Posthog().onFeatureFlags(received.add);
      addTearDown(subscription.unsubscribe);

      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test('does not stop the next load replaying', () async {
      loadFlags(listeners);
      final received = <PostHogFeatureFlagsLoaded>[];
      final subscription = Posthog().onFeatureFlags(received.add);
      addTearDown(subscription.unsubscribe);

      await Future<void>.delayed(Duration.zero);

      expect(received.single.variants, {'on': true});
    });
  });

  test('a reset started by a listener is not undone by the load', () async {
    final listeners = stubPosthogJs();
    FeatureFlagsListeners.instance.clear();

    // What reset() and close() do before reaching the platform.
    final starter = FeatureFlagsListeners.instance
        .add((_) => FeatureFlagsListeners.instance.clear());
    addTearDown(starter.unsubscribe);
    await PosthogFlutterWeb().setup(PostHogConfig('test_project_token'));
    loadFlags(listeners);
    final received = <PostHogFeatureFlagsLoaded>[];
    final subscription = FeatureFlagsListeners.instance.add(received.add);
    addTearDown(subscription.unsubscribe);
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
  });

  test('close() during the synchronous flag replay removes the registration',
      () async {
    final listeners = <JSFunction>[];
    globalContext.setProperty(
        'posthog'.toJS,
        JSObject()
          ..setProperty(
            'onFeatureFlags'.toJS,
            ((JSFunction callback) {
              listeners.add(callback);
              // posthog-js calls back right away when flags are loaded.
              callback.callAsFunction(
                  null, ['on'].jsify(), {'on': true}.jsify(), null);
              return (() => listeners.remove(callback)).toJS;
            }).toJS,
          ));
    addTearDown(() => globalContext.delete('posthog'.toJS));
    final web = PosthogFlutterWeb();

    final closer = FeatureFlagsListeners.instance.add((_) => web.close());
    addTearDown(closer.unsubscribe);
    await web.setup(PostHogConfig('test_project_token'));

    expect(listeners, isEmpty);
  });

  test('registrations queued by the posthog-js loader stop after close()',
      () async {
    // The loader snippet queues calls and returns undefined until it loads.
    final queued = <JSFunction>[];
    globalContext.setProperty(
        'posthog'.toJS,
        JSObject()
          ..setProperty(
            'onFeatureFlags'.toJS,
            ((JSFunction callback) {
              queued.add(callback);
            }).toJS,
          ));
    addTearDown(() => globalContext.delete('posthog'.toJS));
    FeatureFlagsListeners.instance.clear();
    final received = <PostHogFeatureFlagsLoaded>[];
    final subscription = FeatureFlagsListeners.instance.add(received.add);
    addTearDown(subscription.unsubscribe);
    final web = PosthogFlutterWeb();

    await web.setup(PostHogConfig('test_project_token'));
    await web.setup(PostHogConfig('test_project_token'));
    loadFlags(queued);
    await web.close();
    loadFlags(queued);

    expect(received.single.variants, {'on': true});
  });
}
