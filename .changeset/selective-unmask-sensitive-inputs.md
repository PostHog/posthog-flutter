---
"posthog_flutter": minor
---

Add `PostHogUnmaskWidget` to reveal known-safe Flutter text and images while keeping global masking enabled. Unmasking overrides explicit masks in either nesting order, but sensitive inputs stay masked. Protection covers obscured fields, sensitive keyboard types, and standard autofill hints for personal, contact, address, authentication, and payment data across Material, Cupertino, and direct `EditableText` inputs. Nested unmask regions are subtracted from enclosing masks only when their transforms and clips allow a safe rectangular exclusion. On Flutter web, mounting either wrapper enables canvas masking; declare `canvasCapture.maskRegionsFn: () => null` in `posthog.init`'s `session_recording` configuration to protect frames before the first mount. Native platform views and captured native screens are unaffected.
