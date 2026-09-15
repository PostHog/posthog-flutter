---
'posthog_flutter': minor
---

Add `sessionReplayConfig.textMaskPolicy` to mask text at glyph precision instead of all-or-nothing. A policy decides per text node whether to mask all of it, none of it, only some character ranges, or everything except some ranges, so an app can hide amounts and card numbers while the labels around them stay readable. Ships with `PostHogTextMaskPolicies.digits()`, `.redact(RegExp)` and `.reveal(RegExp)`. Applies to `Text`, `RichText`, and non-sensitive text inputs; sensitive inputs, `PostHogMaskWidget`, and `PostHogUnmaskWidget` keep precedence, and the policy fails closed by masking the whole node when it throws or returns a range outside the text.
