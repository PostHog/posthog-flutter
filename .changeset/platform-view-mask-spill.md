---
'posthog_flutter': patch
---

Fix session replay painting a clipped map, WebView, or camera preview past its visible edge and over the widgets around it. A platform view's mask now covers only the part an ancestor clip leaves visible, and a revealed one is clipped to the same region, so widgets a platform view used to bury are visible in replays again
