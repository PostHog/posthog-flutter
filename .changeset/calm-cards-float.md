---
'posthog_flutter': minor
---

Surveys on iOS now follow `appearance.position`. PostHog's default position is bottom right, so default surveys on iOS show as a bottom-right card where they used to open a full-width bottom sheet. To keep the bottom sheet, set the survey position to Bottom center. Android keeps showing the bottom sheet until posthog-android passes the position through.
