import 'dart:io';

import 'src/posthog_desktop_app_info.dart';
import 'src/posthog_desktop_storage.dart';
import 'src/posthog_desktop_time_zone.dart';
import 'src/posthog_flutter_desktop.dart';
import 'src/posthog_flutter_platform_interface.dart';

/// Registers the Windows and Linux implementation of the plugin, which runs
/// in Dart: there is no native PostHog SDK for these platforms.
class PosthogFlutterDart {
  PosthogFlutterDart._();

  /// Installs the implementation for the running app as the platform
  /// instance. Called by the plugin registrant of Windows and Linux apps.
  static void registerWith() {
    final environment = Platform.environment;
    PosthogFlutterPlatformInterface.instance = PosthogFlutterDesktop(
      appDirectory: DesktopStorage.appDirectory(
        environment,
        executable: Platform.resolvedExecutable,
      ),
      appInfo: DesktopAppInfo.fromPlatform(),
      timezone: DesktopTimeZone.read(environment),
    );
  }
}
