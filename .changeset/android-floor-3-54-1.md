---
"posthog_flutter": patch
---

Require posthog-android 3.54.1 or newer. Earlier 3.x versions performed replay work on every touch (a network-time Binder call, a `MotionEvent` copy, and a replay-executor submission) even when session replay was disabled or sampled out, which could cause ANRs on Android. Projects with a Gradle lockfile or cached dependency resolution could stay pinned to an affected version; the raised floor guarantees the fixed SDK.
