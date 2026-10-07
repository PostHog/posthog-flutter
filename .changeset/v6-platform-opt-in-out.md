---
"posthog_flutter": major
---

- **Breaking:** rename `PosthogFlutterPlatformInterface.enable()` and `disable()` to `optIn()` and `optOut()`. Only affects custom platform implementations and test fakes that override them
