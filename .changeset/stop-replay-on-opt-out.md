---
"posthog_flutter": patch
---

Stop Flutter session replay when `optOut()` opts the user out, and start a new recording on `optIn()` if a recording was actually stopped.
