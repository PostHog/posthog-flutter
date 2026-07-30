---
'posthog_flutter': patch
---

Warn in debug builds when `preloadFeatureFlags` or `bootstrap` are set on Flutter web, where they are not applied, and document that `identify`/`group` reload feature flags
