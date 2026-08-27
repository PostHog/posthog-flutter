---
'posthog_flutter': patch
---

Fix session replay masking a platform view past its visible bounds. A map, WebView, or camera preview inside a `ClipRect` or a scroll view reports its full, unclipped size, so the mask was drawn over the whole view and covered the widgets sitting below it. The mask is now intersected with the ancestor clip chain, and revealed views are clipped to the same region when they are composited.

The mask is also re-measured immediately before it is painted and widened to cover both positions if the tree moved mid-capture, so trimming it to the visible region cannot expose masked content during a scroll.
