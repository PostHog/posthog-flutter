---
"posthog_flutter": patch
---

Fix the false "plugins that apply Kotlin Gradle Plugin (KGP)" warning that Flutter 3.44+ printed for `posthog_flutter` on every AGP 9 build, even though the plugin applies KGP only when built-in Kotlin is off.
