---
'posthog_flutter': patch
---

Fix `$push_notification_opened` not being captured on Android when the app is cold-launched from a notification tap. Requires posthog-android 3.62.0.
