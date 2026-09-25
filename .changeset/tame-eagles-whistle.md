---
"posthog_flutter": minor
---

Add the `compression` config (`PostHogCompression.gzip` / `none`) so an app can send request bodies uncompressed, e.g. when a managed network or work profile alters the compressed body in transit.
