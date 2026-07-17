---
"posthog_flutter": patch
---

Android: session replay screenshots are decoded, re-encoded, and queued off the main thread. Previously each frame cost the main thread 25-75ms on midrange hardware (up to once per second while recording), a visible per-second hitch during scrolling — iOS already did this work on a background queue.
