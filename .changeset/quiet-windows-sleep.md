---
"posthog_flutter": patch
---

Android: fix session replay crashing the app with `IllegalArgumentException: Window doesn't have a backing surface!` when the app goes to the background while it captures revealed platform views. A frame with several revealed views captures each one from the previous one's callback, where the exception thrown by `PixelCopy.request` went uncaught on the main thread. A view whose copy throws now comes back empty, which the Dart side already handles like any view it could not capture.
