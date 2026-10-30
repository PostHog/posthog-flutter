---
"posthog_flutter": major
---

- **Breaking:** `beforeSend` and `logsConfig.beforeSend` callbacks are now synchronous (`PostHogEvent? Function(PostHogEvent)` and `PostHogLogRecord? Function(PostHogLogRecord)`), as in the native SDKs. A `reset()`, `identify()` or `optOut()` made right after an un-awaited `capture()`, `screen()` or `captureException()` no longer applies to the event first, and Windows and Linux no longer drop it. Callbacks that used `await` must load what they need ahead of time
