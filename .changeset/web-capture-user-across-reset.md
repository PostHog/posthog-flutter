---
"posthog_flutter": patch
---

Keep events in call order on every platform except Windows and Linux while an async `beforeSend` runs. A `reset()`, `identify()`, `alias()`, `register()`, `group()`, `optIn()` or `optOut()` made after an un-awaited `capture()`, `screen()` or `captureException()` now applies after that event, so the event goes out with the user, super properties, groups and consent it was captured under, as in the native SDKs. While a `beforeSend` callback runs, later PostHog calls (getters included) wait for it; one that runs longer than 10 seconds stops holding them back, and its event is still sent.
