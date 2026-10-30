---
"posthog_flutter": major
---

- **Breaking:** remove `PostHogConfig.onFeatureFlags`; call `Posthog().onFeatureFlags((loaded) { ... })` before `setup()` instead, which also covers the first load
