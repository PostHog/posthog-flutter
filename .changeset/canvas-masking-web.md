---
"posthog_flutter": minor
---

Add session replay canvas masking on Flutter web: `maskAllTexts`, `maskAllImages`, `PostHogMaskWidget`, and obscured text fields now apply to the CanvasKit canvas — enable by declaring `session_recording.canvasCapture.maskRegionsFn` in `posthog.init`, or just by mounting a `PostHogMaskWidget` (requires posthog-js 1.408.0+)
