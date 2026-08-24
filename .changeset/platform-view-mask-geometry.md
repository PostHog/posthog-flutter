---
'posthog_flutter': patch
---

Fix session replay masking on screens with a platform view (map, WebView, camera preview). A revealed view (`maskAllPlatformViews = false`) no longer turns black when the native capture fails — the SDK keeps the Flutter pixels and logs the failure instead. The mask rect is now clipped to the ancestor clip chain, so it no longer spills past the view onto the widgets below. The platform view rects are also collected in the same frame as the widget mask rects, so a mask can no longer land a frame late over moved pixels.
