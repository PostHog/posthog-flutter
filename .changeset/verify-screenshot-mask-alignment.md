---
"posthog_flutter": minor
---

Add `PostHogSessionReplayConfig.verifyScreenshotMaskAlignment` for Android native screens captured with `captureNativeScreens`. Enabling it can preserve screenshots and mask alignment during pixel-only redraws, including continuously animated content, but performs additional view hierarchy walks. It remains disabled by default.
