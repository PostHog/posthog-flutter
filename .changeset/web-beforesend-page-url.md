---
"posthog_flutter": patch
---

Let web `beforeSend` redact `$current_url`, `$host`, and `$pathname`. Those properties are attached before the callback. A removed key is sent as null, because posthog-js fills an omitted one back in from `window.location`.
