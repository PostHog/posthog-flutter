---
"posthog_flutter": major
---

- **Breaking:** `beforeSend` and `logsConfig.beforeSend` callbacks are now synchronous (`PostHogEvent? Function(PostHogEvent)` and `PostHogLogRecord? Function(PostHogLogRecord)`), as in the native SDKs. An event is now handed to the SDK in the same call, so a `reset()`, `identify()` or `optOut()` made right after an un-awaited `capture()`, `screen()` or `captureException()` no longer applies to it first, and Windows and Linux no longer drop it. Callbacks that used `await` must load what they need ahead of time
