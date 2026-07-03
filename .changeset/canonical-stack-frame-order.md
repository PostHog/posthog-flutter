---
"posthog_flutter": minor
---

Emit Dart error-tracking stack frames in PostHog's canonical bottom-up wire order: `$exception_list[].stacktrace.frames[0]` is now the outermost/entry-point frame and the last frame is the crash site (previously innermost-first). Applies to the primary exception and every cause in the chain. Native (Android/iOS) crash paths are unaffected.
