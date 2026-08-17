---
"posthog_flutter": minor
---

Support changing `throttleDelay` at runtime: session replay capture picks up the new cadence the next time it restarts, via `close()`/`setup()` or `stopSessionRecording()`/`startSessionRecording()`

Roll back `setup()` state when the first initialization fails, so nothing is captured and a later `setup()` retries cleanly. A repeated `setup()` that fails leaves the already-working SDK running

Warn when `setup()` is called while already set up, naming what it cannot change without `close()` first — the project token, host and native session replay settings, which both native SDKs keep because they ignore a repeated setup, and the replay capture cadence, which only changes when capture restarts
