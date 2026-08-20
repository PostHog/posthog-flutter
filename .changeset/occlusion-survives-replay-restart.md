---
"posthog_flutter": patch
---

Fix session replay losing the native-screen cover when the session changes while one is up. `reset()`, or a `close()`/`setup()` pair, briefly turns replay off, and the occlusion detector read that as the episode ending — so the Flutter app was recorded from underneath the native screen, and the same screen was then detected again as a new episode. The detector now keeps the episode while the app is still covered.
