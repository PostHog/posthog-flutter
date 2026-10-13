import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'util/logging.dart';

/// Where the Windows and Linux implementation persists its state: queued
/// events, identity, consent and cached feature flags.
class DesktopStorage {
  /// The PostHog directory inside the platform's application support directory.
  /// Returns null when directory lookup or creation fails, so the client can
  /// keep its state in memory.
  static Future<String?> appDirectory() async {
    try {
      final path =
          await PathProviderPlatform.instance.getApplicationSupportPath();
      if (path == null) {
        printIfDebug('[PostHog] No application support directory found; '
            'keeping state in memory only.');
        return null;
      }
      return '$path${Platform.pathSeparator}posthog';
    } catch (e) {
      printIfDebug('[PostHog] Application support directory unavailable; '
          'keeping state in memory only: $e');
      return null;
    }
  }

  /// The directory of the project with [projectToken] in [appDirectory]: a
  /// shared one would mix identity, consent and queued events between
  /// projects.
  static String projectDirectory(String appDirectory, String projectToken) =>
      '$appDirectory${Platform.pathSeparator}${_scope(projectToken)}';

  static String _scope(String value) {
    final scope = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (scope.isEmpty || scope == '.' || scope == '..') return 'default';
    return scope;
  }
}
