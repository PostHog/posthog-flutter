import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_desktop_app_info.dart';
import 'package:posthog_flutter/src/posthog_desktop_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('collectDesktopContext', () {
    test('collects app and os context', () {
      final context = collectDesktopContext(
        const DesktopAppInfo(name: 'TestApp', version: '1.2.3', build: '42'),
      );

      expect(context[r'$app_name'], 'TestApp');
      expect(context[r'$app_version'], '1.2.3');
      expect(context[r'$app_build'], 42);
      expect(context[r'$device_type'], 'Desktop');
      // Host-dependent values: only their shape is stable across runners.
      expect(context[r'$os_name'], anyOf('Windows', 'Linux'));
      expect(context[r'$os_version'], isA<String>());
    });

    test('keeps a build that is not a number as a string', () {
      final context = collectDesktopContext(
        const DesktopAppInfo(build: '1.2.3'),
      );

      expect(context[r'$app_build'], '1.2.3');
    });

    test('omits the app values the build did not record', () {
      final context = collectDesktopContext(const DesktopAppInfo());

      expect(context, isNot(contains(r'$app_name')));
      expect(context, isNot(contains(r'$app_version')));
      expect(context, isNot(contains(r'$app_build')));
    });
  });

  group('extractOsVersion', () {
    const versionByBanner = <String, String>{
      '"Windows 10 Pro" 10.0 (Build 19043)': '10.0.19043',
      'Linux 5.11.0-1018-gcp #20~20.04.1-Ubuntu SMP Fri Sep 3 01:01:37 '
          'UTC 2021': '5.11.0',
    };

    versionByBanner.forEach((banner, version) {
      test('extracts $version from $banner', () {
        expect(extractOsVersion(banner), version);
      });
    });

    test('returns a banner with no recognizable version unchanged', () {
      expect(extractOsVersion('unknown os'), 'unknown os');
    });
  });

  group('parseBuildNumber', () {
    const buildByString = <String, Object>{
      '42': 42,
      '042': 42,
      '1.2.3': '1.2.3',
      '0x10': '0x10',
      '42-beta': '42-beta',
    };

    buildByString.forEach((build, expected) {
      test('parses "$build" as $expected', () {
        expect(parseBuildNumber(build), expected);
      });
    });
  });

  group('languageCodeOf', () {
    test('reports the language without the region', () {
      expect(languageCodeOf(const Locale('en', 'US')), 'en');
      expect(
        languageCodeOf(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        ),
        'zh',
      );
    });

    test('omits locales that name no language', () {
      expect(languageCodeOf(const Locale.fromSubtags()), isNull);
      expect(languageCodeOf(const Locale('C')), isNull);
      expect(languageCodeOf(const Locale('POSIX')), isNull);
    });
  });
}
