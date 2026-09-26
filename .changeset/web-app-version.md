---
"posthog_flutter": minor
---

Attach `$app_version` and `$app_build` to web events, read from the `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER` compile-time constants (Flutter 3.47+), so web events carry the running app's version like iOS and Android do.
