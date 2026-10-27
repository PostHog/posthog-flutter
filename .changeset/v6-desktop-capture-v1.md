---
"posthog_flutter": major
---

- **Breaking:** on Windows and Linux, events now go to capture v1 (`/i/v1/analytics/events`) instead of `/batch/`, like iOS and Android in 6.0. A reverse proxy or self-hosted instance must serve the new path: a 404 is retried, the events stay queued, and the SDK prints a warning once, also without `debug`. Events queued before the upgrade are sent through the new endpoint
- **Breaking:** on Windows and Linux, a redirect drops the batch instead of retrying it (only same-origin 307/308 redirects are followed, while a 404 or 429 is retried), and a `Retry-After` wait is capped at 30 seconds
- On Windows and Linux, once a batch has failed after its retries, later sends make one attempt each and wait longer between them, from 6 up to 30 seconds, until a batch is delivered
