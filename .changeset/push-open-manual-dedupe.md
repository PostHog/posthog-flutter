---
'posthog_flutter': patch
---

Require posthog-android 3.65.0 so a manual `capturePushNotificationOpened` call for a PostHog notification tap the SDK already captured on Android is counted once.
