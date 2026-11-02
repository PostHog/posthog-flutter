---
"posthog_flutter": major
---

- **Breaking:** bump the minimum iOS deployment target from 13.0 to 15.0 and macOS from 10.15 to 11.0 — see the [migration guide](https://github.com/PostHog/posthog-flutter/blob/main/posthog_flutter/MIGRATION.md)
- **Breaking:** remove CocoaPods support on iOS and macOS — install through Swift Package Manager, which needs Flutter 3.41 or later and doesn't support add-to-app modules yet
- **Breaking:** change `getFeatureFlagResult()` to follow `PostHogConfig.sendFeatureFlagEvent` on iOS, macOS, Android, Windows and Linux when `sendFeatureFlagEvent` is omitted — pass `sendFeatureFlagEvent: true` to keep capturing `$feature_flag_called`
- **Breaking:** rename `getFeatureFlagResult(sendEvent:)` to `getFeatureFlagResult(sendFeatureFlagEvent:)`
- **Breaking:** remove `PostHogConfig.apiKey` and the `com.posthog.posthog.API_KEY` manifest and Info.plist key — use `projectToken` and `com.posthog.posthog.PROJECT_TOKEN`
- **Breaking:** remove `Posthog().enable()` and `Posthog().disable()` — use `optIn()` and `optOut()`
- **Breaking:** remove `PostHogConfig.sendFeatureFlagEvents` — use `sendFeatureFlagEvent`
- **Breaking:** remove `Posthog().getFeatureFlagPayload()` — use `getFeatureFlagResult(key, sendFeatureFlagEvent: false)` and read `payload`
- **Breaking:** remove the `PostHogSessionReplayConfig.debouncerDelay` setter — use `throttleDelay`
- **Breaking:** remove `PostHogDataMode.cellular` — use `PostHogDataMode.any`
- **Breaking:** remove `toMap()` from the config classes and `PostHogFeatureFlagResult.fromMap()` from the public API
- **Breaking:** rename `enable()` and `disable()` to `optIn()` and `optOut()` on `PosthogFlutterPlatformInterface`, `PosthogFlutterIO` and `PosthogFlutterWeb`
- Declare Android `minSdkVersion` 23 to match `posthog-android`
- Add a `defaultValue` option to `isFeatureEnabled()`, returned when the flag has no value
