---
"posthog_flutter": patch
---

Fix session replay losing the native-screen cover when a session boundary lands during one. `reset()`, or a `close()`/`setup()` pair, turns replay off for around a second; the occlusion detector read that as the episode ending, so Flutter capture resumed while the native screen was still on top and the same cover was then re-detected as a new episode
