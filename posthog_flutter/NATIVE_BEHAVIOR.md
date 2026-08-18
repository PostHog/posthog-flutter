# Native behaviour this SDK depends on

Session replay in this wrapper reasons about how posthog-android and posthog-ios
manage sessions, because the native SDKs expose no way to push session changes
into Dart. Those assumptions are load-bearing, they are **not** covered by any
test in this repository, and both dependencies are floating ranges:

- `android/build.gradle` → `com.posthog:posthog-android:[3.58.0,4.0.0)`
- `darwin/posthog_flutter/Package.swift` → `posthog-ios "3.69.0" ..< "4.0.0"`
- `darwin/posthog_flutter.podspec` → `PostHog >= 3.69.0, < 4.0.0` (CocoaPods
  consumers resolve through this one, not `Package.swift`)

So a native patch release can silently falsify any row below. This file is the
list to re-check when the resolved native version moves.

Every row below was verified against **posthog-android 3.58.0** (the range floor)
and re-checked at **posthog-android 3.59.0**, which is what the range resolves to
at the time of writing — `PostHogSessionManager.kt` is byte-identical between the
two, and the `PostHog.kt` delta touches only opt-in and error-tracking code. iOS
is **posthog-ios 3.69.0**, the version the example app's `Package.resolved` pins.

To re-resolve Android after a native release:
`cd example/android && ./gradlew :posthog_flutter:dependencies --configuration debugRuntimeClasspath | grep posthog-android`.

| # | Assumption | Android | iOS |
|---|---|---|---|
| 1 | A repeated `setup()` is ignored | `PostHog.kt` — `if (enabled) { log; return }` | `PostHogSDK.swift` — `if enabled { hedgeLog; return }` |
| 2 | The per-tick session read is **non-mutating on both platforms**, so it never moves where expiry is applied. The send resolves the session itself, exactly as before this plugin read the id at all | `PostHogSessionManager.peekSessionId()` — *"Read-only sibling of getActiveSessionId: skips the expiry checks"* | `PostHogSDK.getSessionId()` is hard-wired `readOnly: true` |
| 3 | `reset()` rotates the session | `endSession()` + `startSession()` | `sessionManager.reset()` → `resetSession()` → `rotateSession(force: true)` |
| 4 | `reset()` leaves replay briefly inactive | clears the remote config, and the replay integration stops when the flag is false | `remoteConfig?.clear()` drops `sessionReplayFlagActive`; `isSessionReplayActive()` requires it, and `reloadFeatureFlags()` restores it asynchronously (~120 ms observed) |
| 5 | `close()` and the session id | **keeps** the id: `close()` clears `enabled` before its `endSession()`, which early-returns, and the following `setup()`'s `startSession()` returns early while an id exists | **clears** it: `close()` calls `sessionManager.endSession()` directly, bypassing the `enabled` gate |
| 6 | `startSessionRecording(resumeCurrent: false)` | does **not** rotate while recording: `startSessionReplay` early-returns on `isActive()` | rotates via `getNextSessionId()` even while active |
| 7 | The **send** is what applies the idle and maximum-duration bounds, on both platforms, because the snapshot carries no pre-attached `$session_id` | `RRUtils.capture()` → `PostHog.capture()` → `getActiveSessionId()`, the expiring accessor | `PostHogSDK.capture()` resolves the session at send |
| 8 | The idle clock is refreshed only by user touches and lifecycle transitions — **not** by `capture()` — and `touchSession()` checks only the idle bound, never max-duration. The send-time resolve in row 7 is therefore what keeps a replay-only session bounded | `touchSession()` is called only from `PostHogTouchActivityIntegration` (API ≥ 26) and `PostHogLifecycleObserverIntegration` | touch half gated on `enableSwizzling` (default on) and iOS/tvOS only; the lifecycle half is unconditional |
| 9 | Per-session replay state is reset on rotation | `resetSessionStateIfNeeded(id, force = !resumeCurrent)`, and `start()` force-invalidates decor views on a non-resuming start | `handleSessionChanged` |

## Consequences worth remembering

- Rows 5 and 6 mean the platforms **disagree**, so Dart cannot key "the recording
  restarted" on the session id changing. That is why `reset()`, `close()` and a
  non-resuming start bump `PostHogInternalEvents.forceReplaySessionReset`
  unconditionally.
- Row 4 is why one forced sample is not enough: it can be spent while the
  platform is briefly not recording. See `ChangeDetector.forceNextTicks`.
- Rows 2 and 7 together are why a rotation is seen **one tick late on both
  platforms**: nothing tells Dart the session moved until the next tick reads it.
  A frame captured just before an unforced rotation can therefore land at the head
  of the new session ahead of its meta event; the following tick repairs it. This
  is the accepted trade for a plugin that never pre-attaches an id — pre-attaching
  would fix attribution but move the expiry bounds off the send, which is a larger
  behaviour change than the bug being fixed here warrants.
- Row 7 is why `onSessionRotated` asks for a follow-up sample.

## What would delete rows rather than test them

- Native pushing session-changed events into Dart would remove the polling, the
  forced frames and the retry budget entirely — rows 4, 7, 8 and 9. What blocks
  it is visibility on both sides: Android's `setOnSessionIdChangedListener` is
  `internal` and single-slot, and while iOS's `PostHogSessionManager.shared` is
  `@objc public static`, its `onSessionIdChanged` multicast callback is
  `internal`.
- A public expiring session accessor on posthog-ios would remove the iOS half of
  row 7.
