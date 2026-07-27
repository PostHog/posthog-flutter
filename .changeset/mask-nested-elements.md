---
"posthog_flutter": patch
---

Session replay: masks every element that matched a masking rule, at any depth. The rect collector only walked two levels of the matched-element tree and dropped any node that had more than one matched child, so with `maskAllTexts`/`maskAllImages` enabled a `PostHogMaskWidget` wrapping several masked children lost its own mask rect and anything it wrapped but did not match on its own (an image, an avatar, decoration) stayed visible in the recording.
