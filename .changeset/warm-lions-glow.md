---
'posthog_flutter': minor
---

Enable captureApplicationLifecycleEvents by default and align Android config key name.

Application lifecycle events (`Application Opened`, `Application Backgrounded`, etc.) are now captured by default. If you don't want these events, you can disable them:

- **Dart (recommended):** Set `config.captureApplicationLifecycleEvents = false` in your PostHog configuration.
- **Android (manifest):** Add `<meta-data android:name="com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS" android:value="false" />` to your `AndroidManifest.xml`. The legacy key `com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS` is still supported.
- **iOS/macOS (Info.plist):** Set `com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS` to `NO` in your `Info.plist`.
