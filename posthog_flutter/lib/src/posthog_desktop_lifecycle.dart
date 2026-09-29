import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'posthog_desktop_context.dart';
import 'util/logging.dart';

/// What the Windows and Linux implementation drives from the application
/// lifecycle. A desktop app has no background state, so it counts as opened
/// when it becomes active and as backgrounded when it resigns active:
///
/// - `Application Installed` / `Application Updated` when this launch's
///   version or build differs from the previous launch's;
/// - `Application Opened` / `Application Backgrounded` on those transitions;
/// - a flush of the queue whenever the app resigns active.
///
/// Without a Flutter binding only the install/update check runs.
class DesktopAppLifecycle {
  DesktopAppLifecycle({
    required WidgetsBinding? binding,
    required String storageDirectory,
    required String? version,
    required String? build,
    required bool captureEvents,
    required void Function(String event, Map<String, Object>? properties)
        capture,
    required Future<void> Function() flush,
  })  : _binding = binding,
        _version = version,
        _build = build,
        _captureEvents = captureEvents,
        _capture = capture,
        _flush = flush,
        _versionFile = File(
          '$storageDirectory${Platform.pathSeparator}posthog_app_version.json',
        ) {
    if (binding != null) {
      _listener = AppLifecycleListener(
        binding: binding,
        onResume: _onResume,
        onInactive: _onInactive,
      );
    }
  }

  final String? _version;
  final String? _build;
  final bool _captureEvents;
  final void Function(String event, Map<String, Object>? properties) _capture;
  final Future<void> Function() _flush;

  final WidgetsBinding? _binding;

  /// Holds the version and build of the latest launch. Kept apart from the
  /// SDK state so that reset() does not turn the next launch into an install.
  final File _versionFile;

  AppLifecycleListener? _listener;
  bool _isStarted = false;
  bool _isFreshLaunch = true;
  bool _isBackgrounded = true;

  /// Starts the lifecycle events: records this launch's version and captures
  /// `Application Installed` or `Application Updated`. The app counts as
  /// opened on its next activation, or right away with
  /// [captureOpenedIfActive] when it is active already.
  void start({bool captureOpenedIfActive = false}) {
    if (_isStarted) return;
    _isStarted = true;
    _isFreshLaunch = true;
    _isBackgrounded = true;

    // Recorded even when the events are off, so turning them on later does
    // not report an app that was installed long ago.
    final versionChange = _recordAppVersion();
    if (!_captureEvents) return;

    if (versionChange != null) {
      _capture(versionChange.event, versionChange.properties);
    }
    if (captureOpenedIfActive &&
        _binding?.lifecycleState == AppLifecycleState.resumed) {
      _captureOpened();
    }
  }

  /// Stops the lifecycle events while the user is opted out. The flush on
  /// resign active continues.
  void stop() {
    _isStarted = false;
  }

  void dispose() {
    stop();
    _listener?.dispose();
    _listener = null;
  }

  void _onResume() {
    if (_isStarted && _captureEvents) _captureOpened();
  }

  void _onInactive() {
    if (_isStarted && _captureEvents) _captureBackgrounded();
    _flush().catchError((Object e) {
      printIfDebug('[PostHog] Exception on flush: $e');
    });
  }

  void _captureOpened() {
    if (!_isBackgrounded) return;
    _isBackgrounded = false;

    final properties = <String, Object>{'from_background': !_isFreshLaunch};
    if (_isFreshLaunch) {
      _isFreshLaunch = false;
      _addVersion(properties);
    }
    _capture('Application Opened', properties);
  }

  void _captureBackgrounded() {
    if (_isBackgrounded) return;
    _isBackgrounded = true;
    _capture('Application Backgrounded', null);
  }

  void _addVersion(Map<String, Object> properties) {
    final version = _version;
    final build = _build;
    if (version != null) properties['version'] = version;
    if (build != null) properties['build'] = parseBuildNumber(build);
  }

  /// Records this launch's version and build and returns the event reporting
  /// how they changed since the previous launch, if they did.
  ({String event, Map<String, Object> properties})? _recordAppVersion() {
    // Nothing to compare when the build recorded neither.
    if (_version == null && _build == null) return null;

    Map<String, Object?>? previous;
    try {
      previous =
          jsonDecode(_versionFile.readAsStringSync()) as Map<String, Object?>;
    } on PathNotFoundException {
      // The first launch with the SDK.
    } catch (e) {
      // An unknown previous version must not be reported as an install.
      printIfDebug('[PostHog] Could not read the previous app version: $e');
      _writeAppVersion(_version, _build);
      return null;
    }

    final previousVersion = _stringOrNull(previous?['version']);
    final previousBuild = _stringOrNull(previous?['build']);
    // A value missing from this launch keeps the recorded one, so a later
    // launch still compares against it.
    _writeAppVersion(_version ?? previousVersion, _build ?? previousBuild);

    final properties = <String, Object>{};
    final String event;
    if (previousVersion == null && previousBuild == null) {
      event = 'Application Installed';
    } else {
      // Builds are compared, and versions when the app has no build number.
      final unchanged = _build != null
          ? _build == previousBuild
          : _version == previousVersion;
      if (unchanged) return null;

      event = 'Application Updated';
      if (previousVersion != null) {
        properties['previous_version'] = previousVersion;
      }
      if (previousBuild != null) {
        properties['previous_build'] = parseBuildNumber(previousBuild);
      }
    }
    _addVersion(properties);
    return (event: event, properties: properties);
  }

  void _writeAppVersion(String? version, String? build) {
    try {
      _versionFile.parent.createSync(recursive: true);
      // Atomic replace: a crash mid-write must not lose the recorded version.
      final tmp = File('${_versionFile.path}.tmp');
      tmp.writeAsStringSync(
        jsonEncode({'version': version, 'build': build}),
        flush: true,
      );
      tmp.renameSync(_versionFile.path);
    } catch (e) {
      printIfDebug('[PostHog] Could not record the app version: $e');
    }
  }

  static String? _stringOrNull(Object? value) => value is String ? value : null;
}
