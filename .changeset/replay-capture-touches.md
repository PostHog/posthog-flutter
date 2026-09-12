---
"posthog_flutter": minor
---

Add `sessionReplayConfig.captureTouches` to disable replay touch coordinates during SDK initialization on Android and iOS while keeping masked screenshots. This protects keypad entry whose values can be reconstructed from tap positions. Requires posthog-android 3.64.0 and posthog-ios 3.74.0. Runtime changes are not supported.
