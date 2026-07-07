---
"posthog_flutter": patch
---

Document that `maskAllTexts` and `maskAllImages` have no effect on Flutter web when the CanvasKit renderer is active. posthog-js records the raw `<canvas>` element rather than DOM nodes, so the Dart-side masking pipeline is bypassed entirely. No per-region canvas masking API exists in rrweb today; a complete fix requires overlaying DOM block elements at widget bounds across the CanvasKit compositing boundary.
