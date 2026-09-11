---
"posthog_flutter": minor
---

Add `PostHogUnmaskWidget` to selectively reveal known-safe Flutter text and images while keeping global session replay masking enabled. Explicit masks and sensitive inputs take precedence regardless of nesting. Password, card number/security code, and one-time-code autofill hints, password keyboard types, and obscured fields now stay masked across Material, Cupertino, and direct `EditableText` inputs even when global text masking is disabled. Flutter web still requires canvas masking to be enabled; native platform views and captured native screens are unaffected.
