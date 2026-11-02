---
"posthog_flutter": patch
---

Raise the Android SDK minimum to 3.75.0 to support Firebase Installation ID (FID) push registration when `firebase_messaging_installation_id_enabled` is enabled. With `firebase_messaging` 17+, forward `onRegistered` to the existing `registerPushNotificationToken` method; explicit Android registrations refresh the subscription even when the FID is unchanged. iOS continues to use APNs by default.
