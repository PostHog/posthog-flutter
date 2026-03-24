import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get globalThis;

Map<String, String>? getPosthogChunkIds() {
  final debugIdMapJS = globalThis['_posthogChunkIds'];
  final debugIdMap = debugIdMapJS?.dartify();
  if (debugIdMap == null || debugIdMap is! Map) {
    return null;
  }
  return Map<String, String>.fromEntries(
    debugIdMap.entries.map(
      (e) => MapEntry(e.key.toString(), e.value.toString()),
    ),
  );
}
