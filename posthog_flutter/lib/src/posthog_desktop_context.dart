import 'dart:io';
import 'dart:ui';

import 'posthog_desktop_app_info.dart';
import 'util/logging.dart';

/// Collects the static device and app context of desktop events. App values
/// the build did not record are omitted.
Map<String, Object?> collectDesktopContext(DesktopAppInfo app) {
  final build = app.build;
  return {
    if (app.name != null) r'$app_name': app.name,
    if (app.version != null) r'$app_version': app.version,
    if (build != null) r'$app_build': parseBuildNumber(build),
    r'$os_name': _osName(),
    r'$os_version': extractOsVersion(Platform.operatingSystemVersion),
    r'$device_type': 'Desktop',
    ..._screenInfo(),
  };
}

/// A build number as `$app_build` carries it: an int when [build] is a
/// decimal number, so builds compare as numbers, the string itself otherwise
/// ("1.2.3").
Object parseBuildNumber(String build) =>
    int.tryParse(build, radix: 10) ?? build;

// Only Windows and Linux run this implementation.
String _osName() => Platform.isWindows ? 'Windows' : 'Linux';

/// Extracts the numeric OS version from a [Platform.operatingSystemVersion]
/// banner ('"Windows 10 Pro" 10.0 (Build 19043)',
/// 'Linux 5.11.0-1018-gcp #20~20.04.1-Ubuntu ...').
///
/// Windows banners fold the build number into the version ('10.0.19043');
/// other banners yield their first dotted number. A banner with nothing that
/// looks like a version is returned unchanged.
String extractOsVersion(String banner) {
  final windows = RegExp(r'(\d+\.\d+)\s+\(Build\s+(\d+)\)').firstMatch(banner);
  if (windows != null) return '${windows[1]}.${windows[2]}';
  return RegExp(r'\d+(\.\d+)+').firstMatch(banner)?[0] ?? banner;
}

/// The language code of [locale] ("en"), reported as `$locale`.
///
/// Null when the platform reported no locale ("und") or only the POSIX
/// default Linux falls back to ("C"), which names no language.
String? languageCodeOf(Locale locale) {
  final language = locale.languageCode;
  const noLanguage = {'', 'und', 'C', 'POSIX'};
  return noLanguage.contains(language) ? null : language;
}

/// Screen size in logical pixels.
///
/// Best effort, read once at setup: when the engine has not reported the
/// implicit view's display yet, the keys are omitted instead of being read
/// lazily, keeping the context immutable for the client's lifetime.
Map<String, Object?> _screenInfo() {
  try {
    final display = PlatformDispatcher.instance.implicitView?.display;
    if (display == null) return {};
    final ratio = display.devicePixelRatio;
    final size = display.size;
    if (ratio <= 0 || size.isEmpty) return {};
    return {
      r'$screen_width': (size.width / ratio).round(),
      r'$screen_height': (size.height / ratio).round(),
      r'$screen_density': ratio,
    };
  } catch (e) {
    // FlutterView.display throws while the view is not attached to one.
    printIfDebug('[PostHog] Could not read display info: $e');
    return {};
  }
}
