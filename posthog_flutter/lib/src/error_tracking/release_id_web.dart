import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get globalThis;

/// Reads the release id `posthog-cli sourcemap inject --release-mode=event`
/// writes into each chunk.
///
/// The CLI prepends a snippet that sets `globalThis._posthogReleaseId` to the
/// release row's id, first write wins, so the first loaded chunk pins the
/// release for the runtime. Returns null when nothing was injected or the value
/// is not a non-empty string.
String? getPosthogReleaseId() {
  final releaseIdJS = globalThis['_posthogReleaseId'];
  final releaseId = releaseIdJS?.dartify();
  if (releaseId is! String || releaseId.isEmpty) {
    return null;
  }
  return releaseId;
}
