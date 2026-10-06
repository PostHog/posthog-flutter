// Flutter 3.32+ compiles its own version into every build as this define. It
// backs `FlutterVersion.version`, which can't be referenced directly because
// that class is missing from the older Flutter versions this package supports.
const _flutterVersion = String.fromEnvironment('FLUTTER_VERSION');

/// Returns the `$flutter_version` property, or an empty map when the build
/// doesn't report a Flutter version (Flutter < 3.32).
Map<String, String> flutterVersionProperties({
  String flutterVersion = _flutterVersion,
}) {
  return {
    if (flutterVersion.isNotEmpty) r'$flutter_version': flutterVersion,
  };
}

/// Adds the `$flutter_version` property to [properties], replacing any value
/// the caller set. `beforeSend` runs afterwards and can still change it.
Map<String, Object>? withFlutterVersion(Map<String, Object>? properties) {
  final versionProperties = flutterVersionProperties();
  if (versionProperties.isEmpty) return properties;
  return {...?properties, ...versionProperties};
}
