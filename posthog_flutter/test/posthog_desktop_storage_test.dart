import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_desktop_storage.dart';

void main() {
  final sep = Platform.pathSeparator;

  group('DesktopStorage.appDirectory', () {
    late Directory supportDirectory;

    setUp(() {
      supportDirectory = Directory.systemTemp.createTempSync('posthog_support');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance =
          _PathProvider(() async => supportDirectory.path);
      addTearDown(() {
        PathProviderPlatform.instance = previous;
        supportDirectory.deleteSync(recursive: true);
      });
    });

    test('uses the application support directory with a PostHog subdirectory',
        () async {
      expect(await DesktopStorage.appDirectory(),
          '${supportDirectory.path}${sep}posthog');
    });

    test('preserves spaces and Unicode in the application directory', () async {
      final path = '${supportDirectory.path}${sep}Example é 日本';
      PathProviderPlatform.instance = _PathProvider(() async => path);
      expect(await DesktopStorage.appDirectory(), '$path${sep}posthog');
    });

    test('uses memory-only storage when no directory is available', () async {
      PathProviderPlatform.instance = _PathProvider(() async => null);
      expect(await DesktopStorage.appDirectory(), isNull);
    });

    test('uses memory-only storage when the platform lookup fails', () async {
      PathProviderPlatform.instance = _PathProvider(
          () async => throw PlatformException(code: 'unavailable'));
      expect(await DesktopStorage.appDirectory(), isNull);
    });

    test('uses memory-only storage when the directory cannot be created',
        () async {
      final file = File('${supportDirectory.path}${sep}file')
        ..writeAsStringSync('');
      PathProviderPlatform.instance = _PathProvider(() async {
        final directory = Directory('${file.path}${sep}child');
        await directory.create(recursive: true);
        return directory.path;
      });
      expect(await DesktopStorage.appDirectory(), isNull);
    });
  });

  group('DesktopStorage.projectDirectory', () {
    test('is named after the project token in the app directory', () {
      expect(
        DesktopStorage.projectDirectory('/data/posthog/example', 'phc_1'),
        '/data/posthog/example${sep}phc_1',
      );
    });

    test('never leaves the app directory', () {
      expect(
        DesktopStorage.projectDirectory('/data/posthog/example', '..'),
        '/data/posthog/example${sep}default',
      );
      expect(
        DesktopStorage.projectDirectory('/data/posthog/example', '../../x'),
        '/data/posthog/example$sep.._.._x',
      );
    });
  });
}

class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.resolve);

  final Future<String?> Function() resolve;

  @override
  Future<String?> getApplicationSupportPath() => resolve();
}
