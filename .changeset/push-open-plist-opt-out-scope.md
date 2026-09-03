---
'posthog_flutter': patch
---

Change `com.posthog.posthog.CAPTURE_PUSH_NOTIFICATION_OPENED` to also suppress the new iOS cold-start prewarm in apps that do not use `com.posthog.posthog.AUTO_INIT`.
