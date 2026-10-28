---
'posthog_flutter': minor
---

Add `isolate.addPostHogErrorListener()` and `isolate.removePostHogErrorListener()` to capture uncaught background isolate errors and clean up their listeners, and clarify that `captureIsolateErrors` only monitors the setup isolate.
