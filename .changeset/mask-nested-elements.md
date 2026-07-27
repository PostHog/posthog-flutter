---
"posthog_flutter": patch
---

Session replay: masks every element that matched a masking rule, at any depth. The rect collector only walked two levels of the matched-element tree and dropped any node that had more than one matched child, so with `maskAllTexts`/`maskAllImages` enabled a `PostHogMaskWidget` wrapping several masked children lost its own mask rect, and whatever it wrapped that matched no rule on its own (a decorated container, a chart, a custom-painted avatar) stayed visible in the recording. More of the screen is masked as a result: a `PostHogMaskWidget` now covers its whole subtree, as documented, instead of only the children that matched.
