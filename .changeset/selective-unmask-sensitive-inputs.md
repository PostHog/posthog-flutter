---
"posthog_flutter": minor
---

Add `PostHogUnmaskWidget` to selectively reveal known-safe Flutter text and images while keeping global session replay masking enabled. Explicit masks and sensitive inputs take precedence regardless of nesting. Password, card number/security code/expiration date (including day/month/year), and one-time-code autofill hints, password keyboard types, and obscured fields now stay masked across Material, Cupertino, and direct `EditableText` inputs even when global text masking is disabled. On Flutter web, mounting a mask or unmask widget enables canvas masking. To protect frames before the first mount, declare `canvasCapture.maskRegionsFn: () => null` in `posthog.init`'s `session_recording` configuration. Native platform views and captured native screens are unaffected.
