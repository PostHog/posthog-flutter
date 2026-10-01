---
"posthog_flutter": patch
---

Show a survey that arrives before `PosthogObserver` has a context once the next navigation happens, instead of dropping it and blocking later surveys.
