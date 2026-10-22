---
"posthog_flutter": patch
---

Omit numeric NaN and infinities from Windows/Linux event object properties and send them as null in arrays instead of strings. Preserve array positions and valid neighboring properties, and budget exception steps using their final wire form.
