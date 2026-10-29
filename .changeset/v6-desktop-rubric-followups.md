---
"posthog_flutter": patch
---

- Skip `setup()` with one log line when `projectToken` is a personal API key (`phx_`), so the key is never sent
- On Windows and Linux, stop printing capture's response body in flush error logs, and log how many repeated-uuid copies capture dropped
- On Windows and Linux, drop a batch whose 2xx response has no readable per-event results instead of counting it as delivered, and don't resend it
- On Windows and Linux, log one line per batch that lost events, with the endpoint, the count and capture's reasons, also for a terminal status; a `limited` result counts as delivered, like any result the SDK doesn't know
