---
"posthog_flutter": minor
---

Support changing `throttleDelay` at runtime: session replay capture picks up the new cadence the next time it restarts, via `close()`/`setup()` or `stopSessionRecording()`/`startSessionRecording()`
