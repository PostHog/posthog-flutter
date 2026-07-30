---
"posthog_flutter": minor
---

Change `PostHogMaskWidget` to enable web canvas masking on its own: the first mount opts the app in without the `posthog.init` declaration, restarting an in-flight recording once
