---
"posthog_flutter": patch
---

Warn when PostHogWidget mounts before Posthog().setup() on mobile, explaining that session replay requires setup before mounting or remounting the widget after setup.
