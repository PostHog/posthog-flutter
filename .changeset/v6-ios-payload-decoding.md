---
"posthog_flutter": major
---

- **Breaking:** return `null` instead of the raw string for a malformed, empty, or whitespace-only feature flag payload on iOS and macOS
- **Breaking:** keep bootstrapped string payloads such as `"123"` or `"true"` as strings on iOS and macOS instead of decoding them to numbers or booleans, matching Android
