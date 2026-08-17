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
list to re-check when the resolved native version moves. Verified against
**posthog-android 3.58.0** and **posthog-ios 3.69.0**.

| # | Assumption | Android | iOS |
|---|---|---|---|
| 1 | A repeated `setup()` is ignored | `PostHog.kt` — `if (enabled) { log; return }` | `PostHogSDK.swift` — `if enabled { hedgeLog; return }` |
| 2 | A caller-supplied `$session_id` on `capture()` wins over the id native would resolve itself, so pre-attaching keeps a frame in the session it was captured under — but it also means the send stops applying expiry. This plugin pre-attaches on **Android only**, where the tick read is the expiring accessor and therefore still applies the bounds. posthog-ios's own replay integration pre-attaches an id it read from the *expiring* accessor, which this plugin cannot do: that accessor is `internal`. | `PostHog.kt` — *"Skip the getter when caller pre-attached an id: getActiveSessionId() can silently rotate"* | `PostHogSDK.swift` — *"we attach the session id … as early as possible"*; `PostHogReplayIntegration.swift` uses `getSessionId(at:)` |
| 3 | `reset()` rotates the session | `endSession()` + `startSession()` | `sessionManager.reset()` → `resetSession()` → `rotateSession(force: true)` |
| 4 | `reset()` leaves replay briefly inactive | clears the remote config, and the replay integration stops when the flag is false | `remoteConfig?.clear()` drops `sessionReplayFlagActive`; `isSessionReplayActive()` requires it, and `reloadFeatureFlags()` restores it asynchronously (~120 ms observed) |
| 5 | `close()` and the session id | **keeps** the id: `close()` clears `enabled` before its `endSession()`, which early-returns, and the following `setup()`'s `startSession()` returns early while an id exists | **clears** it: `close()` calls `sessionManager.endSession()` directly, bypassing the `enabled` gate |
| 6 | `startSessionRecording(resumeCurrent: false)` | does **not** rotate while recording: `startSessionReplay` early-returns on `isActive()` | rotates via `getNextSessionId()` even while active |
| 7 | The session accessor used per capture tick differs, and something must apply the expiry bounds on each platform | `PostHog.getSessionId()` — **expiring**; this read is what applies idle/max-duration to Flutter frames, since the send now carries a pre-attached id. Only the native *screenshot* loop is disabled for Flutter (`isNativeSdk`); the touch interceptor still emits `$snapshot` mouse interactions through `RRUtils.capture()`, which pre-attaches nothing and so resolves an expiring id at send | `getSessionId()` is hard-wired `readOnly: true`, so the **send** applies the bounds and a rotation is seen one tick late |
| 8 | The idle clock is refreshed only by user touches and lifecycle transitions — **not** by `capture()` — and `touchSession()` checks only the idle bound, never max-duration. So on each platform at least one thing applies both bounds (row 7), and removing it would let a replay-only session run unbounded | `touchSession()` is called only from `PostHogTouchActivityIntegration` (API ≥ 26) and `PostHogLifecycleObserverIntegration` | touch half gated on `enableSwizzling` (default on) and iOS/tvOS only; the lifecycle half is unconditional |
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
- **Rows 2, 7 and 8 are one constraint, not three.** A frame is attributed
  correctly only if Dart names its session; the expiry bounds are applied only by
  an expiring read. Android can have both (expiring tick read + pre-attach).
  iOS can have either, not both, because its expiring accessor is `internal` — so
  it keeps the bounds and accepts that a rotation is seen a tick late, which
  `onSessionRotated` repairs on the following tick — one bare frame can still land
  in the new session ahead of its meta. **Making posthog-ios's expiring
  accessor public is what would let iOS do what posthog-ios's own replay
  integration already does.**
- The occlusion placeholder reads the *tracked* session id rather than polling,
  so on a static screen it can be stale. There the platforms swap roles: Android
  pre-attaches the dead id and the placeholder appends to the ended recording,
  while iOS resolves at send and gets it right. Cosmetic — the episode-end
  sample repairs the new recording either way.
- Ingestion routes by the supplied id: a `$snapshot` naming a session that
  rotated two hours earlier still appended to that recording. Not verified beyond
  that — an id older than the 24 h maximum is untested, which is another reason
  the bounds must keep being applied.

## What would delete rows rather than test them

- Native pushing session-changed events into Dart would remove the polling, the
  forced frames and the retry budget entirely — rows 4, 7, 8 and 9. What blocks
  it is visibility on both sides: Android's `setOnSessionIdChangedListener` is
  `internal` and single-slot, and while iOS's `PostHogSessionManager.shared` is
  `@objc public static`, its `onSessionIdChanged` multicast callback is
  `internal`.
- A public expiring session accessor on posthog-ios would remove the iOS half of
  row 7.
