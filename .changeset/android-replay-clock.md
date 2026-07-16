---
"posthog_flutter": patch
---

Android: session replay screenshots are now timestamped with the native SDK's clock instead of the system clock. The two can diverge (the SDK prefers the network-time clock on API 33+), which scrambled the replay timeline — frames appeared at a different time than touch events and native-captured screens.
