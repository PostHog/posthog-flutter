---
"posthog_flutter": major
---

- **Breaking:** remove `PostHogConfig.apiKey` and the `com.posthog.posthog.API_KEY` manifest/Info.plist key — use `projectToken` and `com.posthog.posthog.PROJECT_TOKEN`
- **Breaking:** remove `Posthog().getFeatureFlagPayload()` — use `getFeatureFlagResult(key, sendEvent: false)` and read `payload`
- **Breaking:** remove the `PostHogSessionReplayConfig.debouncerDelay` setter — use `PostHogSessionReplayConfig.throttleDelay`
- **Breaking:** remove `PostHogDataMode.cellular` — use `PostHogDataMode.any`, which it always behaved like
