---
"posthog_flutter": patch
---

Convert numeric NaN and infinities in Windows/Linux event properties to JSON null instead of strings, preserving array positions and valid neighboring properties.
