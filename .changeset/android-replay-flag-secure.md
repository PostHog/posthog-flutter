---
'posthog_flutter': patch
---

Mask Android session replay frames while the app window has `FLAG_SECURE` set, instead of recording the secure screen.
