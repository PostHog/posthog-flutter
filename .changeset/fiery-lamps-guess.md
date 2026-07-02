---
"posthog_flutter": minor
---

Platform views are now masked by default in session replay (they now appear as a black box). Use `maskAllPlatformViews = false` to disable masking globally, or wrap individual views in `PostHogPlatformView(privacy: PostHogPlatformViewPrivacy.capture)` to reveal them selectively.
