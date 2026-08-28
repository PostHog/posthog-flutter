---
'posthog_flutter': patch
---

Fix session replay painting a clipped map, WebView, or camera preview past its visible edge and over the widgets around it. Masked regions shrink to what the view actually shows, so widgets a mask used to bury are visible in replays again
