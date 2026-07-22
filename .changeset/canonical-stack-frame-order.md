---
"posthog_flutter": minor
---

Emit Dart error-tracking stack frames in PostHog's canonical bottom-up wire order: `$exception_list[].stacktrace.frames[0]` is now the outermost/entry-point frame and the last frame is the crash site (previously innermost-first). Applies to the primary exception and every cause in the chain. Raise the Android SDK floor to 3.56.0 so native Android exceptions use the same canonical order; Apple-native exceptions already do.
