---
"posthog_flutter": patch
---

Document that on iOS `maskAllPlatformViews = false` and `PostHogPlatformViewPrivacy.capture` only reveal WKWebView-backed `UiKitView`s (maps and other native views stay masked), and log in debug builds when the native side declines a platform view capture and the view is masked instead (#593).
