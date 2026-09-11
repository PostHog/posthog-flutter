---
"posthog_flutter": minor
---

Add `sessionReplayConfig.captureTouches` and an awaitable `Posthog().setCaptureTouches(bool)` on Android and iOS to disable replay touch coordinates while keeping masked screenshots. This protects sensitive keypad entry whose values can be reconstructed from tap positions even when pixels are masked. Requires the native touch-capture controls in posthog-android 3.64.0 and posthog-ios 3.74.0.
