---
"posthog_flutter": minor
---

Change `setup()` to ignore repeated calls until `close()` runs, matching the Android and iOS SDKs, and re-apply all session replay settings (including `throttleDelay`) on a `close()`/`setup()` reconfigure
