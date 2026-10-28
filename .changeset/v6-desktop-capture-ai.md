---
"posthog_flutter": major
---

- **Breaking:** on Windows and Linux, an event's properties are now the ones the SDK sets (device and app context, `$lib`, feature flags, `$session_id`, `$is_identified`, the `$sdk_debug_*` keys), then registered properties, then the event's own, as in `posthog-ios` and `posthog-android` 4.0. A registered or event property with the same name as an SDK property now wins, for that event only. The Dart `beforeSend` callbacks run after that merge, so they see and can change every property and option the SDK adds, and the event is sent as they leave it
- **Breaking:** on Windows and Linux, person processing is sent as the `process_person_profile: false` option only while it is off, instead of a `$process_person_profile` property on every event
- On Windows and Linux, `captureAi` queues AI events on disk apart from other events. The queue keeps up to `captureAiMaxQueueSize` events (100 by default) and 50 MiB, drops a serialized event over `captureAiMaxEventBytes` (8 MiB plus 64 KiB by default, measured before compression) and is sent like other events: same batching, retries and backoff, compressed with `captureAiCompression`, a request failing after `captureAiTimeout` (60 seconds by default) without progress
- On Windows and Linux, an event's timestamp is taken before the `beforeSend` callbacks run
