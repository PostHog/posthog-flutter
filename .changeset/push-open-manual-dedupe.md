---
'posthog_flutter': patch
---

Fix a manual `capturePushNotificationOpened()` call double-counting a PostHog notification tap the SDK already captured; requires posthog-android 3.65.0 and posthog-ios 3.75.0.
