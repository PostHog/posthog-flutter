---
"posthog_flutter": minor
---

Add push notification support so PostHog Workflows can target Flutter apps: device tokens register automatically on iOS and Android, notification opens are captured as `$push_notification_opened`, and `registerPushNotificationToken`, `unregisterPushNotificationToken`, and `capturePushNotificationOpened` cover the refresh and warm-start paths auto-detection cannot see.

Both are **enabled by default**. An app that already has push configured (for example via `firebase_messaging`) starts sending its device token to PostHog after this upgrade with no code change. Set `capturePushNotificationSubscriptions: false` or `capturePushNotificationOpened: false` on `PostHogConfig` to opt out.
