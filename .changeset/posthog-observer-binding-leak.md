---
"posthog_flutter": patch
---

Stop `PosthogObserver` from registering itself with `WidgetsBinding` and never unregistering, which leaked one observer per navigator, such as each nested auto_route router.
