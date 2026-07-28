---
"posthog_flutter": patch
---

Flutter web (WebAssembly): enabling `captureIsolateErrors` no longer crashes the app at startup. The isolate error handler was selected with a `dart.library.html` conditional import, which is false under dart2wasm, so wasm builds compiled the `dart:isolate` implementation and threw `Unsupported operation: RawReceivePort` before `runApp` — a white screen. The import now keys on `dart.library.js_interop` (true for both JS and wasm web builds), and the setup guard also skips isolate wiring on web explicitly. JS web builds and mobile/desktop are unaffected.
