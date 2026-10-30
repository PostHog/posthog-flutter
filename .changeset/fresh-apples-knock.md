---
"posthog_flutter": minor
---

**Breaking:** Change `PostHogSessionReplayConfig.screenshotScale` from `double` to `double?` with a `null` default, so native screens recorded with `captureNativeScreens` on Android pick up posthog-android's one-pixel-per-dp default instead of physical resolution. Flutter screens still capture at one pixel per logical pixel. Set `screenshotScale: 1.0` to keep native screens at physical resolution. Code that reads the value into a `double` needs a null check.
