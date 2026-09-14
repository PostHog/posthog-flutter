---
"posthog_flutter": minor
---

Add `sessionReplayConfig.maskCustomPaint`, defaulting to `false`, to opt into masking the full bounds of custom-painted widgets independently of text and image masking.

Flutter's `maskAllTexts` and `maskAllImages` inspect the widget tree, not arbitrary canvas drawing. Even with those flags enabled, custom-painted text and images require `maskCustomPaint` or an explicit `PostHogMaskWidget`. The new option stays opt-in because it can also mask non-sensitive Material UI, including tab bars, checkboxes, switches, and progress indicators.

Framework scrollbar-only painters are excluded so desktop scrollable viewports remain visible, while their children are still checked for masks. With `maskCustomPaint` enabled, frames containing painters with unknown bounds, including zero-sized painters, are skipped rather than sent unmasked.
