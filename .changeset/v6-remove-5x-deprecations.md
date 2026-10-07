---
"posthog_flutter": major
---

- **Breaking:** remove `Posthog().enable()` and `Posthog().disable()` — use `optIn()` and `optOut()`
- **Breaking:** remove `PostHogConfig.sendFeatureFlagEvents` — use `sendFeatureFlagEvent`
