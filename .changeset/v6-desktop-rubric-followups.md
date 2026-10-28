---
"posthog_flutter": patch
---

- Skip `setup()` with one log line when `projectToken` is a personal API key (`phx_`), so the key is never sent
- On Windows and Linux, stop printing capture's response body in flush error logs, and log how many repeated-uuid copies capture dropped
