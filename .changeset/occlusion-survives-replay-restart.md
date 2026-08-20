---
"posthog_flutter": patch
---

Fix session replay recording the Flutter UI from underneath a native screen when the session changes — `reset()`, or a `close()`/`setup()` pair — while that screen is up.
