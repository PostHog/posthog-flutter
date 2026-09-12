/// No chunk carries a release id outside the web build, so there is nothing to
/// read. Apple and Android exceptions resolve their release from the app
/// metadata the native SDK reports.
String? getPosthogReleaseId() {
  return null;
}
