---
"posthog_flutter": minor
---

Support changing `throttleDelay` at runtime: a `close()`/`setup()` pair now restarts session replay capture at the new cadence, which a repeated `setup()` never did

Roll back `setup()` state when initialization fails, so the SDK is left un-set-up rather than half initialized and a later `setup()` retries cleanly

Warn when `setup()` is called while already set up, naming what it cannot change without `close()` first — the project token, host and native session replay settings, which both native SDKs keep because they ignore a repeated setup, and the replay capture cadence, which only changes when capture restarts
