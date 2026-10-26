---
"posthog_flutter": minor
---

- Add an `options` parameter to `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException`, and `PostHogEvent.options` for `beforeSend` callbacks. The known keys `process_person_profile`, `cookieless_mode`, `disable_skew_correction` and `product_tour_id` win over their legacy `$` properties. On iOS, macOS and Android other keys are sent as-is; on Windows, Linux and web the known keys are sent as their legacy `$` properties and other keys are dropped
- Add `captureAi` for AI observability events such as `$ai_generation`, sent to PostHog's AI endpoint on iOS, macOS and Android, returning the event's UUID. On Windows, Linux and web it sends nothing and returns `null`
- On Windows and Linux, a `$process_person_profile` property passed with an event now applies to that event instead of being replaced by the SDK's value
