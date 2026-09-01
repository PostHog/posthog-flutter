---
'posthog_flutter': patch
---

Change `com.posthog.posthog.CAPTURE_PUSH_NOTIFICATION_OPENED` to opt out of iOS push-open capture in every app, not only those using `com.posthog.posthog.AUTO_INIT`.
