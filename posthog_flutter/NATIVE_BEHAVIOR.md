# Native behaviour this SDK depends on

Session replay in this wrapper reasons about how posthog-android and posthog-ios
manage sessions, because the native SDKs expose no way to push session changes
into Dart. Those assumptions are load-bearing, they are **not** covered by any
test in this repository, and both dependencies are floating ranges:

- `android/build.gradle` → `com.posthog:posthog-android:[3.58.0,4.0.0)`
- `darwin/posthog_flutter/Package.swift` → `posthog-ios "3.69.0" ..< "4.0.0"`

So a native patch release can silently falsify any row below. This file is the
list to re-check when the resolved native version moves. Verified against
**posthog-android 3.58.0** and **posthog-ios 3.69.0**.

| # | Assumption | Android | iOS |
|---|---|---|---|
| 1 | A repeated `setup()` is ignored | `PostHog.kt` — `if (enabled) { log; return }` | `PostHogSDK.swift` — `if enabled { hedgeLog; return }` |
| 2 | A caller-supplied `$session_id` on `capture()` wins over the id native would resolve itself — so pre-attaching it keeps a frame in the session it was captured under. This plugin pre-attaches on both platforms, as posthog-ios's own replay integration does. | `PostHog.kt` — *"Skip the getter when caller pre-attached an id: getActiveSessionId() can silently rotate"* | `PostHogSDK.swift` — *"we attach the session id on the event as early as possible to avoid sending snapshots to a wrong session"* |
| 3 | `reset()` rotates the session | `endSession()` + `startSession()` | `sessionManager.reset()` → `resetSession()` → `rotateSession(force: true)` |
| 4 | `reset()` leaves replay briefly inactive | clears the remote config, and the replay integration stops when the flag is false | `remoteConfig?.clear()` drops `sessionReplayFlagActive`; `isSessionReplayActive()` requires it, and `reloadFeatureFlags()` restores it asynchronously (~120 ms observed) |
| 5 | `close()` and the session id | **keeps** the id: `close()` clears `enabled` before its `endSession()`, which early-returns, and the following `setup()`'s `startSession()` returns early while an id exists | **clears** it: `close()` calls `sessionManager.endSession()` directly, bypassing the `enabled` gate |
| 6 | `startSessionRecording(resumeCurrent: false)` | does **not** rotate while recording: `startSessionReplay` early-returns on `isActive()` | rotates via `getNextSessionId()` even while active |
| 7 | The session accessor used per capture tick is **pure on both platforms** — it cannot rotate a session or stop replay as a side effect, so a rotation is observed on the following tick and the frame in flight is attributed by row 2 | `PostHogSessionManager.peekSessionId()` (public; skips the expiry checks) | `getSessionId()` is hard-wired `readOnly: true` |
| 8 | The idle clock is refreshed only by real user interaction and lifecycle transitions — **not** by `capture()`. So an idle session is not kept alive by replay traffic, and with row 2 in place replay traffic no longer rotates it either | `touchSession()` is called only from `PostHogTouchActivityIntegration` and `PostHogLifecycleObserverIntegration` | equivalent |
| 9 | Per-session replay state is reset on rotation | `resetSessionStateIfNeeded(id, force = !resumeCurrent)`, and `start()` force-invalidates decor views on a non-resuming start | `handleSessionChanged` |

## Consequences worth remembering

- Rows 5 and 6 mean the platforms **disagree**, so Dart cannot key "the recording
  restarted" on the session id changing. That is why `reset()`, `close()` and a
  non-resuming start bump `PostHogInternalEvents.forceReplaySessionReset`
  unconditionally.
- Row 4 is why one forced sample is not enough: it can be spent while the
  platform is briefly not recording. See `ChangeDetector.forceNextTicks`.
- Row 7 (iOS half) is why a rotation is observed a tick late there, and why
  `onSessionRotated` asks for a follow-up sample.
- **Row 2 is what lets row 7 be pure on both platforms.** Because the frame names
  its own session, Dart no longer has to read the id the way `capture()` would,
  so neither platform needs an expiring accessor and the two behave identically.
  Verified against ingestion: a `$snapshot` naming a session that rotated two
  hours earlier still appended to that recording, so routing follows the supplied
  id.
- **Rows 2 and 8 together** mean replay traffic no longer rotates an expired
  Android session. It rolls over on the next real user interaction, as on iOS —
  so an app nobody is using stops minting sessions and recordings.

## What would delete rows rather than test them

- Native pushing session-changed events into Dart (Android's
  `setOnSessionIdChangedListener` is `internal` and single-slot; iOS's
  `sessionManager` is module-internal) would remove the polling, the forced
  frames and the retry budget entirely — rows 4, 7, 8 and 9.
- A public expiring session accessor on posthog-ios would remove the iOS half of
  row 7.
