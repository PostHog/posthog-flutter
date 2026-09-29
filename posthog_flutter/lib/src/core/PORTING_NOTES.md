# Porting notes

The client behind the Windows and Linux implementation of posthog_flutter
(this directory) is a hand-port of `@posthog/core`. The first port was taken
from the `posthog-core` package of
[posthog-js-lite](https://github.com/PostHog/posthog-js-lite) at commit
`1e2e226c59f3c3a63f780d9b61f6d06304f86903`; that repository is archived and
its core now lives in
[posthog-js `packages/core`](https://github.com/PostHog/posthog-js/tree/main/packages/core),
which later behavior (person profiles, `getFeatureFlagResult`) follows.

Only what posthog_flutter calls is ported. For example, there is no
`shutdown()`, `createPersonProfile()`, `onFeatureFlag()`, `resetSessionId()`
or `getFeatureFlagPayload()`, and `reset()` keeps no properties but the device
id.

Deliberate deviations from `@posthog/core`:

| Behavior | `@posthog/core` | This port | Why |
| --- | --- | --- | --- |
| Requests and persistence | Each platform implements `fetch()`, `getPersistedProperty()` and `setPersistedProperty()` | The client sends requests through `dart:io`'s `HttpClient`, honors `PostHogConfig.compression`, and keeps its state and queue in `FileStorage` | Windows and Linux share one implementation |
| Options | `PostHogCoreOptions`, including request timeouts, retries, session expiration, `disabled` and `disableGeoip` | posthog_flutter's `PostHogConfig`. Requests time out after 10 s, a batch is retried 3 times 3 s apart, and a session ends after 30 minutes without events or after 24 hours | posthog_flutter exposes no other options |
| Batch request retries | A fixed delay between attempts, with no pause between retry cycles | Without `Retry-After`, three retries remain 3 s apart. A positive `Retry-After` pauses the whole queue, which manual flush and flushAt do not bypass; close cancels the timer | The server pause matches Android/iOS; behavior without the header is unchanged |
| `before_send` | Runs on every event, SDK-internal ones included | Not in the client: the Windows and Linux implementation runs `PostHogConfig.beforeSend` on the events the app captures, before they reach the client | SDK-internal events and properties stay out of the callbacks, as on the other platforms of posthog_flutter |
| Quota-limited `/flags` response | Unsets all cached flags | Keeps serving cached flags; `quota_limited` is reported only when there is no cached value | Parity with posthog-android / posthog-ios |
| Person properties on `identify()` / `capture()` | Not fed into flag evaluation | `$set` / `$set_once` merge into the persisted person properties for flags (`$set` wins) | Parity with the mobile SDKs |
| Default person properties for flags | Not supported | Sent with every `/flags` request from the `getDefaultPersonPropertiesForFlags()` override; explicitly set properties win | Parity with the mobile SDKs |
| `getFeatureFlag` of an unknown key | `false` once flags are loaded | `null` | posthog_flutter documents `null` for a missing flag; all platforms must answer alike |
| Stopping the client | `shutdown()` sends the queue first; later calls are still enqueued | `close()` sends nothing: requests in flight are aborted, queued events stay stored for the next client, and later calls are ignored with a debug log | `Posthog().close()` must not wait for the network; parity with posthog-ios `close()` |
| Async init guards | `_initPromise` checked in every accessor | None | Dart construction is synchronous; the object is not observable before the constructor returns |
| Event listeners | `on(event, listener)` for every client event, and a `'*'` wildcard | Only `onFeatureFlags()`; debug mode logs the queued, delivered and failed events | posthog_flutter exposes no other listener |
| Flags known at startup | Listeners wait for the next `/flags` response | Flags that are bootstrapped or cached by an earlier run are announced right after the client is created, unless the outcome of a `/flags` request is announced first | The on-feature-flags spec |
| `identify()` | An empty id falls back to the current one; a different id always switches the user | An empty id is ignored; a different id while identified is ignored until `reset()`; the current id sends `$set` instead of `$identify`, and an identified user's new properties do not reload flags | Parity with posthog-ios / posthog-android |
| Calls while opted out | Identity, groups and person properties still change and flags reload; only the event is dropped | `identify`, `alias`, `group`, `setPersonProperties` and `capture` return before changing anything | Parity with posthog-ios and the consent spec |
| `$set` / `$set_once` in `capture()` | Person processing stays as it was | Turns person processing on, so this and later events are person-processed | Parity with posthog-ios / posthog-android |
| `$groups` in `capture()` | Registered as groups for all later events, reloading flags | Sent with that event only | Parity with posthog-ios / posthog-android |
| `group()` | `$groupidentify` only with group properties, which do not feed flags | `$groupidentify` on every call; group properties also feed flag evaluation | Parity with posthog-ios / posthog-android |
| An empty alias, group type or group key | Sent as it is | The call is ignored, with a debug warning | The alias and group specs |
| `$identify`, `$create_alias`, `$groupidentify` | No `$process_person_profile` / `$is_identified` | Both, like every other event | Parity with posthog-ios |
| Opt-out across `reset()` | Persisted opt-out cleared; the configured default applies at once | Persisted opt-out cleared; this client keeps the decision until it is recreated | Parity with posthog-ios / posthog-android, which keep opt-out in memory |
| Consent while the storage cannot be read | No such state | Unknown consent fails closed; `optIn()` / `optOut()` still apply to the running client, and win over the stored decision once it can be read | Tracking without known consent would be worse than dropping events |
| Two instances of the app at once | Left to each platform's storage | The first instance locks the storage. The second keeps its identity and consent changes in memory only, so a `disable()` made there is lost on restart; its events are still stored and sent | The second instance must not overwrite the identity and consent of the first |
| Session | Persisted and resumed after a restart within the inactivity timeout | Kept in memory; every client starts a new session | Parity with posthog-ios |
| `getSessionId()` | Marks the session active and starts a new one after the timeout | Read-only: only events extend or rotate the session | Parity with posthog-ios `getSessionId()` |
| `$timezone` | Not sent | Sent with every event when the host provides it through `getTimezone()` | Parity with posthog-ios |
| Session debug properties | Not sent | `$sdk_debug_session_start`, `$sdk_debug_current_session_duration`, `$sdk_debug_pending_queue_size` on every event | Parity with posthog-ios / posthog-android |
| `/flags` request | No device id; no retries | `$device_id` (the first anonymous id, kept by `reset()`), `timezone` when a platform overrides `getTimezone()`; one retry after 300 ms on network errors and HTTP 502 / 504 | Parity with posthog-ios and the http-client spec |
| Flag payload that is not valid JSON | Returned as the raw string | `null`, with a debug warning | The get-feature-flag-payload spec |
| `$feature_flag_called` deduplication | Per flag, cleared by every flags reload | Per flag and value, cleared by `reset()` | Parity with posthog-ios / posthog-android |
| `$active_feature_flags` | Every loaded flag, disabled ones included | Enabled flags only; left out when there are none | Parity with posthog-ios / posthog-android |
| Null-valued event properties | Sent as JSON `null` | Left out at every level, `$set` / `$set_once` included; array elements keep their positions. Kept only in the `$feature_flag_response` of a flag that has no value | The capture spec |
| Property values JSON cannot represent | `JSON.stringify` rules | Before they reach the client, the values the platform channels cannot carry become their `toString()`, as on the other platforms of posthog_flutter; a `DateTime` in UTC becomes `2025-01-01 00:00:00.000Z`. The client sends NaN and infinite numbers as `"NaN"` / `"Infinity"`, with a debug warning. Applies to events, exception steps, super properties and flag evaluation properties | posthog_flutter normalizes property values alike on every platform |
| Event queue storage | One persisted property, rewritten with every event | A queue of its own in the storage; `FileStorage` writes one file per event and deletes delivered events by id | Parity with posthog-ios: queueing an event does not rewrite the others |
| `maxQueueSize` / `maxBatchSize` | Raised to at least `flushAt` | Applied as configured. A queue capped below `flushAt` is sent by the periodic flush | Parity with posthog-ios / posthog-android; the retry-queue and event-batcher specs |
| HTTP 3xx from `/batch/` | Treated as delivered | Kept queued and retried like a transient failure | Parity with posthog-ios / posthog-android: a POST redirect is not followed, so the events never reached ingestion |
| Queue left by a previous run | Sent with the first flush after a new event | Sent with the first periodic flush after start | Parity with posthog-ios |
| Bootstrap | Identity seeded only when nothing is persisted; persisted flags win over bootstrapped ones; `$used_bootstrap_value` on every `$feature_flag_called` | An identified bootstrap is also reconciled with a stored user; bootstrapped flags replace persisted ones until the first complete `/flags` response; bootstrap properties only for bootstrapped flags | Parity with posthog-ios and the bootstrap spec |

## Desktop and mobile platform contracts

The Flutter public API is shared, but Android and iOS differ in behavior. Regular super properties use `event > session > registered`: this is the contract of `registerForSession`, Android, and the Behavior section of the [register spec](https://github.com/PostHog/sdk-specs/blob/main/openspec/specs/register/spec.md). The [capture spec](https://github.com/PostHog/sdk-specs/blob/main/openspec/specs/capture/spec.md) describes the reverse registered priority used by iOS. Desktop keeps its documented order. The SDK still generates OS/app context, SDK metadata, flags, and person-processing hints. A non-empty caller `$session_id` applies to its event only; the internal session continues to track activity.

An invalid registered `$groups` remains a custom property, but is not interpreted as membership: only string pairs are used for person processing and flags. Valid maps from previous runs continue to work without migration. The new maxQueueSize applies to a persisted queue before its first send.

Flags responses support rich `flags` and legacy `featureFlags`/`featureFlagPayloads`. When the rich field is present, it determines the result, even when the map is empty. The same cache, quota, and partial-response rules apply to both formats.

Bootstrap persists, `getSessionId()` remains read-only, and disable does not delete exception steps that have already been recorded. This matches iOS; exception steps also follow their own spec. `sendFeatureFlagEvents=false` disables exposure events but preserves flags context in capture. An invalid JSON payload returns null according to the payload spec, although mobile implementations may return the original string.

The Windows time zone is read during plugin registration through the system ICU from System32. A `TZ` value with an IANA name takes precedence. ICU is included with Windows; the combined icu.dll in use is available from Windows 10 1903. If the library is unavailable or the zone is unknown, the time zone is omitted and the SDK continues to run. This is best effort, with no custom Windows/IANA table or observer for system time zone changes. Sources: [Microsoft ICU](https://learn.microsoft.com/windows/win32/intl/international-components-for-unicode--icu-), [ICU Calendar API](https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/ucal_8h.html).

Desktop storage uses the user's application data directory. A custom `XDG_DATA_HOME` or `APPDATA` must point to a directory for that user; access to ordinary files is controlled by operating system permissions and umask.

Structured logs, session replay, surveys, push, and native crash hooks are not yet implemented on desktop. A shared Flutter method does not imply transport support on every platform. The shared facade runs beforeSend for logs, but desktop captureLog does not send entries.

Desktop lifecycle is focus-based: Backgrounded and Opened match posthog-macos `ApplicationLifecyclePublisher`'s `applicationDidResignActive` and `applicationDidBecomeActive` notifications (e751c190, lines 97-110).

The desktop adapter also retains three limitations of the current Flutter API on mobile. Consent and the active client are resolved after an asynchronous `beforeSend`, so enabling analytics or replacing the client while the callback is pending can change where the event is sent. Reading a flag while opted out consumes its exposure deduplication entry, as in the native mobile SDKs. Renaming a screen or exception event in `beforeSend` routes it through capture and runs the callback again, as in the Flutter IO adapter. These behaviors need a coordinated cross-platform change rather than a desktop-only contract.
