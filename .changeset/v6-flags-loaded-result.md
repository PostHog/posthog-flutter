---
"posthog_flutter": major
---

- **Breaking:** `PostHogConfig.onFeatureFlags` now receives a `PostHogFeatureFlagsLoaded` with the enabled flags, their values and whether loading failed. Update callbacks from `() { ... }` to `(loaded) { ... }` (or `(_) { ... }`)
- **Breaking:** `reloadFeatureFlags()` now returns a `Future<PostHogFeatureFlagsLoaded>` with the reloaded flags. On web it completes right away with the flags loaded so far
