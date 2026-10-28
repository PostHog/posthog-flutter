---
"posthog_flutter": minor
---

- Add an `options` parameter to `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException`, and `PostHogEvent.options` for `beforeSend` callbacks. The known keys `process_person_profile`, `cookieless_mode`, `disable_skew_correction` and `product_tour_id` win over their legacy `$` properties. On iOS, macOS, Android, Windows and Linux other keys are sent as-is; on web the known keys are sent as their legacy `$` properties and other keys are dropped
- Add `captureAi` for AI observability events such as `$ai_generation`, sent to PostHog's AI endpoint on iOS, macOS, Android, Windows and Linux, returning the event's UUID, or `null` when the event isn't admitted (dropped by `beforeSend`, oversized, SDK disabled or opted out). On web `captureAi` is a no-op: it sends nothing and returns `null`
- Add `PostHogConfig.captureAiCompression`, `captureAiMaxQueueSize`, `captureAiTimeout` and `captureAiMaxEventBytes` for the `captureAi` queue and requests. Unset, they keep the SDK defaults. They have no effect on web
- On Windows and Linux, a `$process_person_profile` property or `process_person_profile` option passed with an event now applies to that event instead of being replaced by the SDK's value
