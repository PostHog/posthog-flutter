---
"posthog_flutter": patch
---

Stop Flutter session replay when `disable()` opts the user out, and start a new recording on `enable()` if a recording was actually stopped.
