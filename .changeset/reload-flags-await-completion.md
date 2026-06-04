---
"posthog_flutter": patch
---

`reloadFeatureFlags()` now resolves its `Future` only after feature flags have finished loading, instead of returning immediately. `await Posthog().reloadFeatureFlags()` is now reliable, so reading a flag (or starting session recording) right after a reload sees the up-to-date result.
