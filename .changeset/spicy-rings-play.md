---
"posthog_flutter": patch
---

Remove `$sdk_debug_session_start` and `$sdk_debug_current_session_duration` from Windows and Linux events, which have no session replay.
