---
'posthog_flutter': patch
---

Keep identifying while opted out on Windows and Linux: `identify()` now updates the distinct id, the person properties used for flag evaluation and reloads feature flags, and only leaves out the `$identify`/`$set` event. The dropped event is no longer remembered as sent, so the same properties are still captured after `optIn()`. iOS, macOS and Android already behaved this way.
