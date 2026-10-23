---
"posthog_flutter": major
---

- **Breaking:** `getFeatureFlagResult()` now follows `PostHogConfig.sendFeatureFlagEvent` when `sendFeatureFlagEvent` is omitted, instead of always capturing `$feature_flag_called`. Pass `sendFeatureFlagEvent: true` to keep capturing the event when the config turns it off
