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
| 2 | `setup()` failure is not reported to the caller | whole body wrapped in `catch (e: Throwable)` | non-`throws`, no blanket catch |
| 3 | `setup()` does not roll back on failure | `enabled = true` is set partway through; the outer catch only logs, so a later failure strands the SDK | n/a |
| 4 | `reset()` rotates the session | `endSession()` + `startSession()` | `sessionManager.reset()` → `resetSession()` → `rotateSession(force: true)` |
| 5 | `reset()` leaves replay briefly inactive | clears the remote config, and the replay integration stops when the flag is false | `remoteConfig?.clear()` drops `sessionReplayFlagActive`; `isSessionReplayActive()` requires it, and `reloadFeatureFlags()` restores it asynchronously (~120 ms observed) |
| 6 | `close()` and the session id | **keeps** the id: `close()` clears `enabled` before its `endSession()`, which early-returns, and the following `setup()`'s `startSession()` returns early while an id exists | **clears** it: `close()` calls `sessionManager.endSession()` directly, bypassing the `enabled` gate |
| 7 | `startSessionRecording(resumeCurrent: false)` | does **not** rotate while recording: `startSessionReplay` early-returns on `isActive()` | rotates via `getNextSessionId()` even while active |
| 8 | The session accessor used per capture tick | `PostHog.getSessionId()` is the **expiring** accessor — applies idle/max-duration, rotates in foreground, clears while backgrounded. It does **not** refresh the activity clock (only `touchSession`/`rotateLocked` write it), so polling cannot keep a session alive | `getSessionId()` is hard-wired `readOnly: true`; the expiring accessor is `internal`, so a rotation is seen one tick late |
| 9 | Resolving the session id can stop replay | a rotation notifies `onSessionIdChanged()`, which calls `stop()` **synchronously** when event triggers are configured — hence the read order in `getSessionReplayState`, pinned by `PosthogFlutterPluginTest.sessionReplayState_resolvesSessionIdBeforeIsActive` | n/a |
| 10 | Per-session replay state is reset on rotation | `resetSessionStateIfNeeded(id, force = !resumeCurrent)`, and `start()` force-invalidates decor views on a non-resuming start | `handleSessionChanged` |

## Consequences worth remembering

- Rows 6 and 7 mean the platforms **disagree**, so Dart cannot key "the recording
  restarted" on the session id changing. That is why `reset()`, `close()` and a
  non-resuming start bump `PostHogInternalEvents.forceReplaySessionReset`
  unconditionally.
- Row 5 is why one forced sample is not enough: it can be spent while the
  platform is briefly not recording. See `ChangeDetector.forceNextTicks`.
- Row 8 (iOS half) is why a rotation is observed a tick late there, and why
  `onSessionRotated` asks for a follow-up sample.

## What would delete rows rather than test them

- Native pushing session-changed events into Dart (Android's
  `setOnSessionIdChangedListener` is `internal` and single-slot; iOS's
  `sessionManager` is module-internal) would remove the polling, the forced
  frames and the retry budget entirely — rows 5, 8, 9, 10.
- A public expiring session accessor on posthog-ios would remove the iOS half of
  row 8.
