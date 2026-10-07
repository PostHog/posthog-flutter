---
"posthog_flutter": major
---

- **Breaking:** remove `PostHogConfig.apiKey` and the `com.posthog.posthog.API_KEY` manifest/Info.plist key — use `projectToken` and `com.posthog.posthog.PROJECT_TOKEN`
- **Breaking:** remove `Posthog().getFeatureFlagPayload()` — use `getFeatureFlagResult(key, sendFeatureFlagEvent: false)` and read `payload`
- **Breaking:** remove the `PostHogSessionReplayConfig.debouncerDelay` setter — use `PostHogSessionReplayConfig.throttleDelay`
- **Breaking:** remove `PostHogDataMode.cellular` — use `PostHogDataMode.any`, which it always behaved like
- Declare Android `minSdkVersion` 23 to match `posthog-android`, which has required it since 3.39.0. Apps on minSdk 21 or 22 already could not build with this plugin, so nothing changes for them
