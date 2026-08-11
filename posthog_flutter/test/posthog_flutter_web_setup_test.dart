@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/posthog_flutter_web.dart';

/// posthog-js is initialized by the host app on web, so options the plugin
/// cannot forward must warn instead of silently doing nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
