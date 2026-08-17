---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session changes or the recording restarts — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`

**Changed:** on Android, session replay no longer rotates an idle session by itself. Snapshots now name the session they were captured under, so an expired session rolls over on the next real user interaction rather than on the next replay capture — matching iOS. An app left running with nobody using it therefore stops producing new sessions and new recordings on the idle timeout; this reduces session counts and replay volume for that case
