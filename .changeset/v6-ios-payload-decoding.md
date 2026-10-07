---
"posthog_flutter": major
---

- **Breaking:** return `null` instead of the raw string for a malformed, empty, or whitespace-only `getFeatureFlagResult()` payload on iOS and macOS
- **Breaking:** keep string payloads passed to `PostHogBootstrapConfig.featureFlagPayloads`, such as `"123"`, as strings on iOS and macOS instead of decoding them to numbers or booleans
