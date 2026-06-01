---
"posthog_flutter": patch
---

Fix link-type survey questions with no URL silently failing to render on Android. The deserializer now treats a missing link as an empty string instead of throwing on `null`.
