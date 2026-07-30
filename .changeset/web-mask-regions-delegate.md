---
"posthog_flutter": patch
---

Fix web canvas masking discarding an app-provided `maskRegionsFn` — canvases outside the Flutter view now get the app's original callback instead of recording unmasked
