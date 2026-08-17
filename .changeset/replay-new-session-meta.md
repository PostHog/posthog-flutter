---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session changes or the recording restarts — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`

**Changed:** with session replay enabled on Android, an idle session now expires on schedule rather than waiting for the next captured event, touch or foreground/background transition — a replay capture is enough to roll it over, so `$session_id` moves sooner on ordinary events too. An app parked in the foreground on a slowly-changing screen will start a new session, and a new recording, roughly every idle timeout instead of none; this shows up in session and recording counts. A capture still needs a rendered frame, so a screen producing no frames at all is unchanged, and iOS is unaffected because its session accessor is read-only
