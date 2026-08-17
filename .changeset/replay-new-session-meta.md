---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session rotates — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`

Change Android session handling so an expired session rolls over on the next replay capture tick instead of waiting for the next captured event or user interaction — with session replay enabled this also moves `$session_id` on ordinary events, which previously kept the expired id until something was captured
