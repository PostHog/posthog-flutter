---
"posthog_flutter": minor
---

Support changing `throttleDelay` at runtime: session replay capture picks up the new cadence the next time it restarts, via `close()`/`setup()` or `stopSessionRecording()`/`startSessionRecording()`

Roll back `setup()` state when the first initialization fails, so nothing is captured and a later `setup()` retries cleanly. A repeated `setup()` that fails leaves the already-working SDK running

Warn when `setup()` is called while already set up, naming what it cannot change without `close()` first: the project token, host and native session replay settings, and whether session replay runs at all. Masking and other Flutter-side settings do follow the new config
