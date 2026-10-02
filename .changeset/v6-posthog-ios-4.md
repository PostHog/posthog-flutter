---
"posthog_flutter": major
---

- **Breaking:** bump minimum iOS deployment target from 13.0 to 15.0 and require Xcode 26, adopting `posthog-ios` 4.x
- **Breaking:** remove `PostHogConfig.apiKey` and the `com.posthog.posthog.API_KEY` manifest/Info.plist key — use `projectToken` and `com.posthog.posthog.PROJECT_TOKEN`
- **Breaking:** remove `Posthog().getFeatureFlagPayload()` — use `getFeatureFlagResult(key, sendEvent: false)` and read `payload`
- **Breaking:** remove the `PostHogConfig.debouncerDelay` setter — use `throttleDelay`
- **Breaking:** remove `PostHogDataMode.cellular` — use `PostHogDataMode.any`, which it always behaved like
