---
'posthog_flutter': patch
---

Fix `$push_notification_opened` being lost on Android when a notification tap reaches the app before `Posthog().setup()` runs and the app's FCM layer does not refresh the Activity intent.
