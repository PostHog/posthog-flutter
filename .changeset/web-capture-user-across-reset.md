---
"posthog_flutter": patch
---

Send web events as the user they were captured for when `reset()` follows an un-awaited `capture()`, `screen()` or `captureException()`. Without `beforeSend` callbacks the event now goes to posthog-js right away; when callbacks run and the user changes before they finish, the event keeps the original `distinct_id`.
