---
"posthog_flutter": major
---

- **Breaking:** remove `toMap()` from the config classes and `PostHogFeatureFlagResult.fromMap()` from the public API — they serialize the internal platform-channel wire format and were never meant for app code
