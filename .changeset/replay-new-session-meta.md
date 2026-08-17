---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session changes or the recording restarts — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`

**Changed:** on Android the session id is now read once per replay tick rather than resolved when the snapshot is sent, so an idle or 24-hour-expired session rolls over a step earlier — including on ticks whose frame is deduplicated or dropped. Sessions already rolled over on replay traffic before this release, so session and recording counts are broadly unchanged; what changes is that the new recording is no longer blank. A tick still needs a rendered frame, so a screen producing no frames at all is unchanged, and iOS is unaffected because its public session accessor is read-only
