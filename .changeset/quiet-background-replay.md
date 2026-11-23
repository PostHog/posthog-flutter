---
"posthog_flutter": patch
---

Skip Session Replay screenshot capture when the Flutter app leaves the foreground to avoid rasterizing frames after Android loses the window surface.
