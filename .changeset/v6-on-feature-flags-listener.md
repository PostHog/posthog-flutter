---
"posthog_flutter": minor
---

- Add `Posthog().onFeatureFlags()` to get notified after every feature flags load, returning a `PostHogFeatureFlagsSubscription` you can `unsubscribe()`
