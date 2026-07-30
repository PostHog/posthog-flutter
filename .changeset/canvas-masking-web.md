---
"posthog_flutter": minor
---

Add session replay canvas masking on Flutter web: `maskAllTexts`, `maskAllImages`, `PostHogMaskWidget`, and obscured text fields now apply to the CanvasKit canvas (requires posthog-js 1.408.0+; enable by declaring `session_recording.canvasCapture.maskRegionsFn` in `posthog.init`)
