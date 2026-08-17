---
'posthog_flutter': minor
---

Add `errorTrackingConfig.captureNativeCrashes` to capture native C/C++ (NDK) crashes on Android. Requires Android 12 (API 31) and `captureNativeExceptions`; crashes are captured on the next app launch and symbolicated against `.so` debug symbols uploaded with the PostHog Gradle plugin.
