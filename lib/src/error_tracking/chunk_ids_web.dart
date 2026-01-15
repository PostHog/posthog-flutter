import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get globalThis;

Map<String, String>? getPosthogChunkIds() {
  final debugIdMapJS = globalThis['_posthogChunkIds'];
  final debugIdMap = debugIdMapJS?.dartify() as Map<dynamic, dynamic>?;
  if (debugIdMap == null) {
    return null;
  }
  return debugIdMap.map(
    (key, value) => MapEntry(key.toString(), value.toString()),
  );
}
