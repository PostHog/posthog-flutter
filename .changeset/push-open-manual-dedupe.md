---
'posthog_flutter': patch
---

Fix a manual `capturePushNotificationOpened()` call double-counting a PostHog notification tap the SDK already captured, using the dedupe added in `posthog-android` 3.65.0 and `posthog-ios` 3.75.0. Update the native SDKs to `posthog-android` 3.65.2 and `posthog-ios` 3.75.2.
