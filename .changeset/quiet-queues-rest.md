---
"posthog_flutter": patch
---

Only attach `$sdk_debug_pending_queue_size` to Windows and Linux events once the event queue reaches `flushAt`, so healthy queues no longer add it to every event
