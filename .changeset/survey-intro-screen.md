---
"posthog_flutter": minor
---

Surveys can now display an optional intro screen before the first question, configured via the new `displayIntroScreen`, `introScreenHeader`, `introScreenDescription`, `introScreenDescriptionContentType`, and `introScreenButtonText` appearance fields. The intro is rendered by the Dart survey UI as the leading mirror of the confirmation message: advancing past it records no response and sends no survey event, while closing the survey from the intro still sends the normal `survey dismissed` event. Requires posthog-ios >= 3.70.0 and posthog-android >= 3.59.0, which forward the new appearance fields over the bridge.
