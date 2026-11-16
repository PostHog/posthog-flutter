import 'dart:convert';
import 'dart:io';

import 'posthog_desktop_version_resource.dart';
import 'util/logging.dart';

/// The name, version and build of a Windows or Linux app.
class DesktopAppInfo {
  const DesktopAppInfo({this.name, this.version, this.build});

  /// What the Flutter build recorded for the running app. Values that cannot
  /// be read are null.
  factory DesktopAppInfo.fromPlatform() {
    try {
      if (Platform.isLinux) {
        return DesktopAppInfo.fromLinuxBundle(Platform.resolvedExecutable);
      }
      if (Platform.isWindows) {
        final resource = WindowsVersionResource.read(
          Platform.resolvedExecutable,
        );
        return DesktopAppInfo.fromVersionResource(
          productName: resource.productName,
          productVersion: resource.productVersion,
        );
      }
    } catch (e) {
      printIfDebug('[PostHog] Could not read the app name and version: $e');
    }
    return const DesktopAppInfo();
  }

  /// Reads the `version.json` that a Linux build bundles in
  /// `data/flutter_assets`, next to the [executable].
  factory DesktopAppInfo.fromLinuxBundle(String executable) {
    final versionFile = File(
      '${File(executable).parent.path}/data/flutter_assets/version.json',
    );
    final json = jsonDecode(versionFile.readAsStringSync());
    if (json is! Map<String, Object?>) return const DesktopAppInfo();
    return DesktopAppInfo(
      name: _nonEmpty(json['app_name']),
      version: _nonEmpty(json['version']),
      build: _nonEmpty(json['build_number']),
    );
  }

  /// Reads the strings of a Windows version resource, whose `ProductVersion`
  /// the Flutter runner sets to the full app version, e.g. `1.2.3+4`.
  factory DesktopAppInfo.fromVersionResource({
    String? productName,
    String? productVersion,
  }) {
    final separator = productVersion?.indexOf('+') ?? -1;
    return DesktopAppInfo(
      name: _nonEmpty(productName),
      version: _nonEmpty(
        separator < 0
            ? productVersion
            : productVersion!.substring(0, separator),
      ),
      build: _nonEmpty(
        separator < 0 ? null : productVersion!.substring(separator + 1),
      ),
    );
  }

  /// The app name: the pubspec `name` on Linux, the `ProductName` of the
  /// executable on Windows.
  final String? name;

  /// The app version without the build number, e.g. `1.2.3`.
  final String? version;

  /// The build number, e.g. `4` for version `1.2.3+4`.
  final String? build;

  static String? _nonEmpty(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
