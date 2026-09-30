---
'posthog_flutter': patch
---
Stop calling the deprecated `getFeatureFlagPayload` of the PostHog iOS SDK on iOS and macOS, which is removed in its next major version.
