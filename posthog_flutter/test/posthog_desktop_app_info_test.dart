import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_desktop_app_info.dart';

void main() {
  group('DesktopAppInfo.fromLinuxBundle', () {
    late Directory bundle;

    setUp(() {
      bundle = Directory.systemTemp.createTempSync('posthog_bundle');
      addTearDown(() => bundle.deleteSync(recursive: true));
    });

    void writeVersionJson(String content) {
      File('${bundle.path}/data/flutter_assets/version.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    test('reads the version.json bundled next to the executable', () {
      writeVersionJson(
        '{"app_name":"example_app","version":"1.2.3",'
        '"build_number":"4","package_name":"example_app"}',
      );

      final info = DesktopAppInfo.fromLinuxBundle('${bundle.path}/example_app');

      expect(info.name, 'example_app');
      expect(info.version, '1.2.3');
      expect(info.build, '4');
    });

    test('leaves out what the pubspec does not declare', () {
      writeVersionJson('{"app_name":"example_app","package_name":"x"}');

      final info = DesktopAppInfo.fromLinuxBundle('${bundle.path}/example_app');

      expect(info.name, 'example_app');
      expect(info.version, isNull);
      expect(info.build, isNull);
    });
  });

  group('DesktopAppInfo.fromPlatform', () {
    test('leaves out what the running executable does not record', () {
      // The tests run in flutter_tester, which bundles no version.json.
      final info = DesktopAppInfo.fromPlatform();

      expect(info.name, isNull);
      expect(info.version, isNull);
      expect(info.build, isNull);
    }, testOn: '!windows');
  });

  group('DesktopAppInfo.fromVersionResource', () {
    test('splits the product version into the version and the build', () {
      final info = DesktopAppInfo.fromVersionResource(
        productName: 'example_app',
        productVersion: '1.2.3+4',
      );

      expect(info.name, 'example_app');
      expect(info.version, '1.2.3');
      expect(info.build, '4');
    });

    test('keeps a pre-release in the version', () {
      final info = DesktopAppInfo.fromVersionResource(
        productVersion: '2.0.0-beta.1+17',
      );

      expect(info.version, '2.0.0-beta.1');
      expect(info.build, '17');
    });

    test('has no build for a version without one', () {
      final info = DesktopAppInfo.fromVersionResource(productVersion: '1.2.3');

      expect(info.version, '1.2.3');
      expect(info.build, isNull);
    });

    test('treats empty strings as missing', () {
      final info = DesktopAppInfo.fromVersionResource(
        productName: '',
        productVersion: '',
      );

      expect(info.name, isNull);
      expect(info.version, isNull);
      expect(info.build, isNull);
    });
  });
}
