---
"posthog_flutter": major
---

- **Breaking:** rename `enable()`/`disable()` to `optIn()`/`optOut()` on `PosthogFlutterPlatformInterface`, `PosthogFlutterIO` and `PosthogFlutterWeb`. Update direct calls to these platform classes, custom implementations, and test fakes/mocks. Calls to `Posthog().optIn()`/`optOut()` are unchanged
