---
"posthog_flutter": major
---

- **Breaking:** on every platform, events now go to capture v1 (`/i/v1/analytics/events`) instead of `/batch/`: iOS and macOS through `posthog-ios` 4.x, Android through `posthog-android` 4.x, and Windows and Linux in the Dart client. If you send events through your own reverse proxy, update it before you upgrade: forward `/i/v1/analytics/events` and `/i/v1/ai/events`, pass `Authorization` (the project token, sent as `Bearer <token>`), every `PostHog-*` header, `Content-Type`, `Content-Encoding` and `User-Agent` through unchanged, and accept request bodies up to 20 MB. PostHog's managed reverse proxy already does this. See the [iOS](https://github.com/PostHog/posthog-ios/blob/main/docs/migration-3.x-to-4.0.md#hosts-without-capture-v1) and [Android](https://github.com/PostHog/posthog-android/blob/main/docs/migration-3.x-to-4.0.md#hosts-without-capture-v1) migration guides
- **Breaking:** on Windows and Linux, a reverse proxy or self-hosted instance must serve the new path: a 404 drops the events. Events queued before the upgrade are sent through the new endpoint
- **Breaking:** on Windows and Linux, a 429 or a redirect drops the batch instead of retrying it (only same-origin 307/308 redirects are followed), and a `Retry-After` wait is capped at 30 seconds
