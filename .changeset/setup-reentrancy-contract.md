---
"posthog_flutter": minor
---

**Breaking:** ignore repeated `setup()` calls until `close()` runs, matching the Android and iOS SDKs — changing session replay settings such as `maskAllTexts` or `maskAllImages` through a second `setup()` now requires calling `close()` first

Support changing `throttleDelay` at runtime: a `close()`/`setup()` pair now restarts session replay capture at the new cadence, which a repeated `setup()` never did

**Breaking:** stop propagating initialization errors out of `setup()` (including `MissingPluginException`) and roll its state back when initialization fails, so a failed `setup()` can be retried
