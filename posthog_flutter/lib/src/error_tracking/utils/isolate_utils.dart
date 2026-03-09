import '_io_isolate_utils.dart'
    if (dart.library.js_interop) '_web_isolate_utils.dart' as platform;

/// Gets the current isolate's debug name
/// Returns null if the name cannot be determined
String? getIsolateName() => platform.getIsolateName();

/// Determines if the current isolate is the root/main isolate
/// Returns true for the main isolate, false for background isolates
bool isRootIsolate() => platform.isRootIsolate();
