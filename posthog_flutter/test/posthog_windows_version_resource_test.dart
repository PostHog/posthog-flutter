@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog_desktop_app_info.dart';
import 'package:posthog_flutter/src/posthog_desktop_version_resource.dart';

void main() {
  const executable = String.fromEnvironment('POSTHOG_TEST_EXECUTABLE');

  test('reads the built runner version resource from a Unicode path', () {
    final directory = Directory.systemTemp.createTempSync('posthog_é_日本_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final copied = File(executable).copySync('${directory.path}/runner_é.exe');

    final resource = WindowsVersionResource.read(copied.path);
    expect(resource.productName, 'posthog_flutter_example');
    expect(resource.productVersion, '1.2.3+456');

    final info = DesktopAppInfo.fromVersionResource(
      productName: resource.productName,
      productVersion: resource.productVersion,
    );
    expect(info.name, 'posthog_flutter_example');
    expect(info.version, '1.2.3');
    expect(info.build, '456');
  }, skip: executable.isEmpty ? 'Requires the built Windows example.' : false);
}
