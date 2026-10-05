---
"posthog_flutter": minor
---

Add `$flutter_version` (for example `3.32.0`) to events captured through `capture`, `screen` and `captureException`. Requires apps built with Flutter 3.32 or later; it's omitted on older Flutter versions and on events the native iOS/Android SDKs or posthog-js capture on their own, such as lifecycle events.
