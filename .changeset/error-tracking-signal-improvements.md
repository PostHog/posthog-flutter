---
"posthog_flutter": minor
---

Improve error-tracking cause handling: `captureException` now walks an error's cause chain (`AsyncError`, `ParallelWaitError`, and exceptions exposing a `cause` getter) into multiple `$exception_list` items, outermost-first (wrapper first, root cause last), with a cycle guard and a depth cap of 10.
