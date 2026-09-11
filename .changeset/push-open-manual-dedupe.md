---
'posthog_flutter': patch
---

Stop double-counting `$push_notification_opened` on Android when a manual `capturePushNotificationOpened` call repeats a PostHog notification tap the SDK already captured.
