---
'posthog_flutter': patch
---

Surveys on iOS now follow `appearance.position`. Top, middle, bottom-left, and bottom-right positions show the survey as a card in that spot, and bottom center keeps the bottom sheet. This needs posthog-ios 3.95.0 or later. Android keeps showing the bottom sheet until posthog-android passes the position through.
