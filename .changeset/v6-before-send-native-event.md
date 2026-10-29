---
"posthog_flutter": major
---

- **Breaking:** On iOS, macOS and Android, `beforeSend` callbacks now get the event the native SDK built, with its system and registered properties, and their changes are final, matching Windows and Linux
- Add `PostHogEvent.uuid`, `distinctId` and `timestamp`, set on every platform but web; a callback can change the distinct ID and timestamp, and the event keeps its uuid
- On Windows and Linux, attach `$exception_steps` before the `beforeSend` callbacks run, as on iOS and Android, so they can read or remove them; steps recorded while a callback runs, or an event a callback renames to `$exception`, no longer get them
- Add `PosthogFlutterPlugin.addBeforeSend` in Swift and Kotlin to filter or edit events the native SDK captures itself, such as crashes, app lifecycle and `$feature_flag_called` events
