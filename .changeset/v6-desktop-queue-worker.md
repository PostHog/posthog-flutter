---
"posthog_flutter": major
---

- On Windows and Linux, encoding queued events, writing and reading their files, and compressing requests now run on a background isolate instead of the UI isolate, so a large `captureAi` event or a full batch no longer drops frames.
- **Breaking:** on Windows and Linux, an event is no longer on disk when `capture`, `screen`, `captureException`, `captureFeatureView`, `captureFeatureInteraction`, `identify`, `alias`, `group` or `setPersonProperties` returns, only when the returned future completes, so one not awaited can be lost if the app crashes or calls `exit()` right after. Await the call, or `Posthog().close()`, before calling `exit()`; only `close()` also covers events the SDK captures itself, such as `$feature_flag_called`. An `identify` not awaited before `exit()` can lose its `$identify` event for good, because the new id is already saved and the event is not sent again. `close()` can now take up to 4 seconds, and a later `setup()` waits for the queue's file work to finish.
