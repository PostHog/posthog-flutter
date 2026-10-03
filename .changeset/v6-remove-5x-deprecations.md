---
"posthog_flutter": major
---

- **Breaking:** make `PostHogWidgetState` and `PostHogMaskWidgetState` private; use `PostHogWidget` and `PostHogMaskWidget`
- **Breaking:** remove `Posthog().enable()` and `Posthog().disable()` — use `optIn()` and `optOut()`
- **Breaking:** remove `PostHogConfig.sendFeatureFlagEvents` — use `sendFeatureFlagEvent`
