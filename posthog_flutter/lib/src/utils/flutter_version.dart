// Flutter 3.32+ compiles its own version into every build as this define. It
// backs `FlutterVersion.version`, which can't be referenced directly because
// that class is missing from the older Flutter versions this package supports.
const _flutterVersion = String.fromEnvironment('FLUTTER_VERSION');

/// Returns the `flutterVersion` setup argument, or an empty map when the build
/// doesn't report a Flutter version (Flutter < 3.32).
///
/// The native plugins add it as `$flutter_version` to the
/// `Application Installed` and `Application Updated` events the native SDKs
/// capture, since the version only changes with a new app build.
Map<String, String> flutterVersionSetupArguments({
  String flutterVersion = _flutterVersion,
}) {
  return {
    if (flutterVersion.isNotEmpty) 'flutterVersion': flutterVersion,
  };
}
