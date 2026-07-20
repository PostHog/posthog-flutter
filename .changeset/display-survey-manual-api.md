---
"posthog_flutter": minor
---

Add `Posthog().displaySurvey(surveyId)` to display a survey on demand, bypassing display conditions (targeting flags, event triggers, and seen/wait-period checks). This is the counterpart of the web SDK's `posthog.displaySurvey()` and also enables API-type surveys, which are never auto-displayed. On Android and iOS the survey is displayed by the native SDK (requires posthog-android >= 3.56.0 / posthog-ios >= 3.67.0); on Web it is displayed by the JS SDK as a popover.
