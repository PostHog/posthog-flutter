---
'posthog_flutter': patch
---

Fix `$push_notification_opened` not being captured on iOS when the app is cold-launched from a notification tap. Requires posthog-ios 3.72.0, and your app must set `UNUserNotificationCenter.current().delegate` — without one iOS reports the tap to nobody.
