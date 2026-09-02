---
'posthog_flutter': minor
---

Capture `$push_notification_opened` on Android for every notification tap, both on a cold launch and while the app is already running. Remove any manual `capturePushNotificationOpened` call wired to `FirebaseMessaging.onMessageOpenedApp` or `getInitialMessage()` — that tap is now captured automatically and the manual call is not deduplicated against it. Requires posthog-android 3.62.0.
