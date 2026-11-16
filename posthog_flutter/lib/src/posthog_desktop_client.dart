import 'dart:ui';

import 'core/posthog_core.dart';
import 'posthog_desktop_context.dart';
import 'posthog_flutter_version.dart';

/// The PostHog client of the Windows and Linux implementation.
///
/// Attaches the static context collected at setup and the current locale to
/// every event. The context is held per instance and never persisted, so each
/// setup() ships fresh values: an updated `$app_version` cannot be shadowed
/// by a stale copy from a previous run.
class DesktopPostHog extends PostHogCore {
  DesktopPostHog(
    super.config, {
    required super.storage,
    required Map<String, Object?> staticContext,
    required String? timezone,
  })  : _staticContext = staticContext,
        _timezone = timezone;

  final Map<String, Object?> _staticContext;

  /// The IANA name of the local time zone.
  final String? _timezone;

  @override
  Map<String, Object?> getContextProperties() {
    final language = languageCodeOf(PlatformDispatcher.instance.locale);
    return {
      ..._staticContext,
      if (language != null) r'$locale': language,
    };
  }

  // Session replay is not available on desktop. Common properties are merged
  // over the event's own, so an event cannot change it.
  @override
  Map<String, Object?> getCommonEventProperties() => {
        ...super.getCommonEventProperties(),
        r'$recording_status': 'disabled',
      };

  @override
  String? getTimezone() => _timezone;

  /// Default person properties sent with every /flags request, so flags can
  /// target the app version, the OS and the device type.
  @override
  Map<String, Object?> getDefaultPersonPropertiesForFlags() => {
        for (final key in _flagPersonPropertyKeys)
          if (_staticContext.containsKey(key)) key: _staticContext[key],
        r'$lib': postHogFlutterSdkName,
        r'$lib_version': postHogFlutterVersion,
      };

  static const _flagPersonPropertyKeys = [
    r'$app_version',
    r'$app_build',
    r'$os_name',
    r'$os_version',
    r'$device_type',
  ];
}
