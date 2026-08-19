---
'posthog_flutter': minor
---

Support light and dark theming for surveys. Read `rgb()`, `rgba()`, `hsl()`, and `hsla()` colors from the server appearance, log a debug warning when a color value cannot be read instead of falling back silently, and let the app supply light and dark `SurveyAppearance` overrides through `PostHogConfig.surveyAppearanceConfig`.
