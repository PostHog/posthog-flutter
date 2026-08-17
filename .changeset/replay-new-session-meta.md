---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session changes or the recording restarts — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`

**Changed:** on Android the session id is now read once per replay tick rather than resolved when the snapshot is sent, so an idle or 24-hour-expired session rolls over a step earlier — including on ticks whose frame is deduplicated or dropped. Sessions already rolled over on replay traffic before this release, so session and recording counts are broadly unchanged; what changes is that the new recording is no longer blank. Ordinary ticks still only sample when the screen renders, so the steady-state cadence on a static screen is unchanged — but capture now forces one frame when it starts and after a session change, where a screen that never repainted previously produced nothing. iOS is unaffected because its public session accessor is read-only
