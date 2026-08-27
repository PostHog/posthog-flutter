---
'posthog_flutter': patch
---

Fix session replay masking a platform view past its visible bounds. A map, WebView, or camera preview inside a `ClipRect` or a scroll view reports its full, unclipped size, so the mask was drawn over the whole view and covered the widgets sitting below it. The mask is now intersected with the ancestor clip chain, and a revealed view is clipped to the same region when it is composited.

Masked regions are correspondingly smaller than before: content that a clipped platform view never actually showed on screen is no longer covered in replay.
