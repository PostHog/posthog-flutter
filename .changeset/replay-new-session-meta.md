---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session changes or the recording restarts — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`

Change Android session handling so an expired session rolls over on the next replay capture tick instead of waiting for the next captured event or user interaction — with session replay enabled this also moves `$session_id` on ordinary events, which previously kept the expired id until something was captured. An app left in the foreground on a screen that never changes therefore starts a new session, and a new recording, when the old one expires, where it previously started neither. iOS is unaffected: its session accessor is read-only, so a Flutter capture tick never rotates the session there
