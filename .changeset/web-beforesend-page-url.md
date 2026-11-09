---
"posthog_flutter": patch
---

Let web `beforeSend` redact `$current_url`, `$host`, and `$pathname`. Those properties are attached before the callback, and the web handler does not put them back.
