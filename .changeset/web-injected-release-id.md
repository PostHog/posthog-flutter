---
"posthog_flutter": minor
---

Report the release id `posthog-cli sourcemap inject --release-mode=event` writes into a Flutter web bundle as `$release_id` on `$exception` events, so PostHog resolves the release per event instead of joining through the uploaded symbol set. The SDK reads the injected global itself, so the release lands whatever posthog-js version the page loaded.
