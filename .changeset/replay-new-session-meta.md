---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session rotates — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`
