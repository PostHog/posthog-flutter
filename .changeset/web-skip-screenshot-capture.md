---
"posthog_flutter": patch
---

Flutter web: `PostHogWidget` no longer runs the mobile session replay screenshot pipeline. On web, session replay is recorded by posthog-js, and every snapshot this pipeline produced was discarded — but it still walked the whole render tree twice per second (once for `PostHogMaskWidget` wrappers, once more when `maskAllTexts` or `maskAllImages` is on) for as long as the app was open. Web apps that enable `sessionReplay` and mount `PostHogWidget` no longer pay for that. Replay on web is unaffected, and `PostHogWidget` still mounts as before, so it remains safe to keep in a shared widget tree across web and mobile.
