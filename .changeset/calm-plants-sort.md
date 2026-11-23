---
"posthog_flutter": patch
---

Fix session replay capturing screenshots while the app is not in the foreground, which could crash Impeller on Android when the app moves to the background.
