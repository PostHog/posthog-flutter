---
"posthog_flutter": patch
---

Fix mobile session replay producing a blank recording after the session changes or the recording restarts — on idle or maximum-duration expiry, `reset()`, `close()`/`setup()`, or `startSessionRecording(resumeCurrent: false)`

**Changed:** on Android the session id is now read once per replay tick rather than resolved when the snapshot is sent, so an idle or 24-hour-expired session rolls over a step earlier — including on ticks whose frame is deduplicated or dropped. Sessions already rolled over on replay traffic before this release, so session and recording counts are broadly unchanged — the exception is an app that renders continuously but whose every replay frame is deduplicated, which previously sent nothing and so never rolled over on replay alone; what changes is that the new recording is no longer blank. Ordinary ticks still only sample when the screen renders, so the steady-state cadence on a static screen is unchanged — but capture now forces a frame when it starts and after a session change, retrying for up to three further ticks until one is delivered, where a screen that never repainted previously produced nothing. iOS rollover timing is unaffected because its public session accessor is read-only — the blank-recording fix itself applies to both platforms
