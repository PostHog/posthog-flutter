---
"posthog_flutter": patch
---

Mask the full bounds of `CustomPaint` widgets with a painter or foreground painter when either `maskAllTexts` or `maskAllImages` is enabled, preventing custom-painted text and images from appearing unmasked in session replay. This also masks children and custom-painted Flutter decorations within those bounds.
