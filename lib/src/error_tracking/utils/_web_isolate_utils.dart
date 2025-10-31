/// Gets the current isolate's debug name for web platforms
/// Web is single-threaded, so always returns 'main'
String? getIsolateName() => 'main';

/// Determines if the current isolate is the root isolate for web platforms
/// Web is single-threaded, so always returns true
bool isRootIsolate() => true;
