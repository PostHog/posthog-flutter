---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session changes or the recording restarts — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`. The new session now sends its own meta event and is sampled even on a screen that never repaints
