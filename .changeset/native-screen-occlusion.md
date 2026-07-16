---
"posthog_flutter": minor
---

Session replay can now capture native screens that cover the Flutter app (full-screen paywalls, presented view controllers, native activities). Opt in with `captureNativeScreens = true`: while a native screen is up, capture is handed to the native PostHog SDK so it becomes visible in replay (requires native SDK support). When enabled but the capture cannot be produced, a black placeholder frame is shown for that screen instead. Off by default — with the flag off nothing is captured or blanked, and replay keeps showing the covered Flutter UI as before. Captured native screens honor your app-wide `maskAllTexts`/`maskAllImages` settings; setting them false reveals native text/images too, including native input fields.

Not captured:

- Partial-height sheets (Apple Pay, share sheet, `.pageSheet`/`.formSheet` modals)
- Content rendered by another process (Apple Pay, photo picker) — blank if the surrounding screen is captured
- Android: anything that is not a full activity in your app's process (Chrome Custom Tabs, Google Pay, dialogs, bottom sheets, permission prompts)
- iOS: covers without an opaque background (camera previews, image/blur backdrops)

Screens that are not captured keep the previous behavior: replay keeps showing the covered Flutter UI.

The flag can also be toggled at runtime. Turning it off takes effect immediately: toggling off right before presenting a sensitive native screen guarantees that screen is not captured. Enable it before presenting a screen you want captured — enabling while a native screen is already up may not capture that screen.

Requires posthog-ios >= 3.66.0 and posthog-android >= 3.55.0 (resolved automatically by the bundled dependency ranges).
