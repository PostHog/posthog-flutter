import 'dart:io';

import 'util/logging.dart';

/// Where the Windows and Linux implementation persists its state: queued
/// events, identity, consent and cached feature flags.
class DesktopStorage {
  /// The directory of the app at [executable] in the user's application data
  /// directory: `%APPDATA%\posthog\<executable name>` on Windows,
  /// `$XDG_DATA_HOME/posthog/<executable name>` (or under
  /// `~/.local/share`) on Linux, read from [environment].
  ///
  /// The executable name identifies the app because it stays the same across
  /// releases; renaming the executable starts over with an empty state.
  static String appDirectory(
    Map<String, String> environment, {
    required String executable,
  }) {
    String? base;
    if (Platform.isWindows) {
      base = environment['APPDATA'] ?? environment['LOCALAPPDATA'];
    } else {
      base = environment['XDG_DATA_HOME'];
      if (base == null || base.isEmpty) {
        final home = environment['HOME'];
        if (home != null && home.isNotEmpty) {
          base = '$home/.local/share';
        }
      }
    }
    if (base == null || base.isEmpty) {
      // FileStorage creates the directory itself; the fallback must stay
      // scoped or it reopens the shared cross-project store.
      base = Directory.systemTemp.path;
      printIfDebug(
          '[PostHog] No application data directory found; persisting events '
          'under $base, which the OS may clear at any time.');
    }

    final sep = Platform.pathSeparator;
    return '$base${sep}posthog$sep${_scope(_executableName(executable))}';
  }

  /// The directory of the project with [projectToken] in [appDirectory]: a
  /// shared one would mix identity, consent and queued events between
  /// projects.
  static String projectDirectory(String appDirectory, String projectToken) =>
      '$appDirectory${Platform.pathSeparator}${_scope(projectToken)}';

  /// The file name of [executable] without the `.exe` extension of Windows
  /// executables.
  static String _executableName(String executable) {
    final name = executable.split(RegExp(r'[/\\]')).last;
    return name.toLowerCase().endsWith('.exe')
        ? name.substring(0, name.length - '.exe'.length)
        : name;
  }

  static String _scope(String value) {
    final scope = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (scope.isEmpty || scope == '.' || scope == '..') return 'default';
    return scope;
  }
}
