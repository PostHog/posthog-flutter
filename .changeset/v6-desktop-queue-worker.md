---
"posthog_flutter": patch
---

- On Windows and Linux, encoding queued events, writing and reading their files, and compressing requests now run on a background isolate instead of the UI isolate, so a large `captureAi` event or a full batch no longer drops frames. An event captured just before the app crashes can be lost, as on Android
