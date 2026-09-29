import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_desktop_storage.dart';

void main() {
  final sep = Platform.pathSeparator;

  group('DesktopStorage.appDirectory', () {
    // The application data directory: APPDATA on Windows, XDG_DATA_HOME on
    // Linux.
    const environment = {'APPDATA': '/data', 'XDG_DATA_HOME': '/data'};

    test('is named after the executable in the application data directory', () {
      expect(
        DesktopStorage.appDirectory(
          environment,
          executable: '/opt/example/example_app',
        ),
        '/data${sep}posthog${sep}example_app',
      );
    });

    test('leaves out the .exe extension', () {
      expect(
        DesktopStorage.appDirectory(
          environment,
          executable: r'C:\Program Files\Example\Example.EXE',
        ),
        '/data${sep}posthog${sep}Example',
      );
    });

    test('replaces characters that do not belong in a directory name', () {
      expect(
        DesktopStorage.appDirectory(
          environment,
          executable: '/opt/example/example app',
        ),
        '/data${sep}posthog${sep}example_app',
      );
    });

    test('is under ~/.local/share without XDG_DATA_HOME', () {
      expect(
        DesktopStorage.appDirectory(
          {'HOME': '/home/user'},
          executable: '/opt/example/example_app',
        ),
        '/home/user/.local/share/posthog/example_app',
      );
    }, testOn: '!windows');

    test('is in the temporary directory without an application data one', () {
      expect(
        DesktopStorage.appDirectory(
          const {},
          executable: '/opt/example/example_app',
        ),
        '${Directory.systemTemp.path}${sep}posthog${sep}example_app',
      );
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
