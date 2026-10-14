---
'posthog_flutter': patch
---

Keep surveys working on Android after a repeated `setup()` call. The native SDK ignores a repeated setup and keeps the survey delegate from the first one, but the plugin built a new delegate and routed all survey actions to it. Every action then failed as `SurveyInvalidated`, so a displayed survey captured no `survey shown`, `survey sent` or `survey dismissed` event, discarded the user's answer, and was never recorded as seen. A recurring survey came back on every launch. A Flutter hot restart runs `main()` again, so it hits this path.
