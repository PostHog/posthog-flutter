---
"posthog_flutter": patch
---

Fix a session replay leak where masks could miss moving content. The mask rects are now computed in the same frame as the captured pixels, and a failed mask walk drops the frame instead of shipping an unmasked screenshot.
