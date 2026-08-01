---
"posthog_flutter": minor
---

**Breaking:** ignore repeated `setup()` calls until `close()` runs, matching the Android and iOS SDKs — changing session replay settings such as `maskAllTexts`, `maskAllImages` or `throttleDelay` through a second `setup()` now requires calling `close()` first
