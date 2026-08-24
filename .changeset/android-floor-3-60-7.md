---
"posthog_flutter": patch
---

Require posthog-android 3.60.7 or newer. Versions 3.43.2 through 3.60.4 stopped a manually started session replay (`sessionReplay: false` plus `startSessionRecording()`) as soon as it started, and 3.60.5/3.60.6 still lost it permanently after the session was cleared on a long background. Projects with a Gradle lockfile or cached dependency resolution could stay pinned to an affected version; the raised floor guarantees the fixed SDK.
