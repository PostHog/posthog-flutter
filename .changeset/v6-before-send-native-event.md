---
"posthog_flutter": major
---

- **Breaking:** On iOS, macOS and Android, `beforeSend` callbacks now get the event the native SDK built, with its system and registered properties, and their changes are final, matching Windows and Linux
- Add `PostHogEvent.uuid`, `distinctId` and `timestamp`, set on iOS, macOS and Android
- Add `PosthogFlutterPlugin.addBeforeSend` in Swift and Kotlin to filter or edit events the native SDK captures itself, such as crashes, app lifecycle and `$feature_flag_called` events
