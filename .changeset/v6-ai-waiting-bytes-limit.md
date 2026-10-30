---
"posthog_flutter": patch
---

- On Windows and Linux, AI events waiting to be written to disk are limited to about 50 MiB in memory, so a burst of unawaited `captureAi` calls no longer holds up to `captureAiMaxQueueSize` large events. The oldest waiting events are dropped first, and `captureAi` completes with `null` for them
