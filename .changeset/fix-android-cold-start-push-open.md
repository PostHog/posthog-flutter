---
'posthog_flutter': patch
---

Fix `$push_notification_opened` not being captured on Android, both on a cold launch from a notification tap and on a tap while the app is already running. Requires posthog-android 3.62.0.
