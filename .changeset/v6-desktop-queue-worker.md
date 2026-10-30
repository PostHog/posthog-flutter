---
"posthog_flutter": major
---

- On Windows and Linux, encoding queued events, writing and reading their files, and compressing requests now run on a background isolate instead of the UI isolate, so a large `captureAi` event or a full batch no longer drops frames.
- **Breaking:** on Windows and Linux, an event is no longer on disk when its capture call returns, only when the returned future completes, so one not awaited can be lost if the app crashes or calls `exit()` right after. Await the capture call, or `Posthog().close()`, before calling `exit()`. `close()` can now take up to 4 seconds, and a later `setup()` waits for the queue's file work to finish.
