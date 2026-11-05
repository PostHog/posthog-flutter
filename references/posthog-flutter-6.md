---
title: "PostHog Flutter SDK 6.x (experimental)"
sidebar: Docs
showTitle: true
contentMaxWidthClass: max-w-full
platformLogo: flutter
tableOfContents:
  - value: "Getting started"
    url: getting-started
    depth: 0
  - value: "Setup"
    url: setup
    depth: 0
  - value: "Capture"
    url: capture
    depth: 0
  - value: "Identify"
    url: identify
    depth: 0
  - value: "Logs"
    url: logs
    depth: 0
  - value: "Alias"
    url: alias
    depth: 0
  - value: "Capture exception"
    url: capture-exception
    depth: 0
  - value: "Debug"
    url: debug
    depth: 0
  - value: "Exception steps"
    url: exception-steps
    depth: 0
  - value: "Flush"
    url: flush
    depth: 0
  - value: "Get distinct ID"
    url: get-distinct-id
    depth: 0
  - value: "Get feature flag"
    url: get-feature-flag
    depth: 0
  - value: "Get feature flag result"
    url: get-feature-flag-result
    depth: 0
  - value: "Get feature flags"
    url: get-feature-flags
    depth: 0
  - value: "Get session ID"
    url: get-session-id
    depth: 0
  - value: "Group"
    url: group
    depth: 0
  - value: "Is feature enabled"
    url: is-feature-enabled
    depth: 0
  - value: "Is opt out"
    url: is-opt-out
    depth: 0
  - value: "Is session replay active"
    url: is-session-replay-active
    depth: 0
  - value: "Opt in"
    url: opt-in
    depth: 0
  - value: "Register"
    url: register
    depth: 0
  - value: "Reload feature flags"
    url: reload-feature-flags
    depth: 0
  - value: "Reset"
    url: reset
    depth: 0
  - value: "Reset group properties for flags"
    url: reset-group-properties-for-flags
    depth: 0
  - value: "Reset person properties for flags"
    url: reset-person-properties-for-flags
    depth: 0
  - value: "Screen"
    url: screen
    depth: 0
  - value: "Set group properties for flags"
    url: set-group-properties-for-flags
    depth: 0
  - value: "Set person properties"
    url: set-person-properties
    depth: 0
  - value: "Set person properties for flags"
    url: set-person-properties-for-flags
    depth: 0
  - value: "Shutdown"
    url: shutdown
    depth: 0
  - value: "Start session recording"
    url: start-session-recording
    depth: 0
  - value: "Stop session recording"
    url: stop-session-recording
    depth: 0
  - value: "Unregister"
    url: unregister
    depth: 0
  - value: "SDK utils"
    url: sdk-utils
    depth: 0
  - value: "PostHogIsolateExtension"
    url: posthogisolateextension
    depth: 0
  - value: "PostHogLogger"
    url: posthoglogger
    depth: 0
  - value: "PostHogMaskWidget"
    url: posthogmaskwidget
    depth: 0
  - value: "PostHogPlatformView"
    url: posthogplatformview
    depth: 0
  - value: "PostHogUnmaskWidget"
    url: posthogunmaskwidget
    depth: 0
  - value: "PostHogWidget"
    url: posthogwidget
    depth: 0
  - value: "PosthogObserver"
    url: posthogobserver
    depth: 0
  - value: "Types"
    url: types
    depth: 0
---

## Getting started


Install the package:

```bash
flutter pub add posthog_flutter
```

Initialize the SDK once, before `runApp`, with your project token and host:

```dart
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = PostHogConfig('<ph_project_token>');
  config.host = 'https://us.i.posthog.com';
  await Posthog().setup(config);

  runApp(const MyApp());
}
```

Capture an event and identify the user:

```dart
await Posthog().capture(eventName: 'user_signed_up', properties: {'plan': 'free'});
await Posthog().identify(userId: 'user_123', userProperties: {'email': 'a@example.com'});
```

Flush queued events and shut the SDK down before the app exits:

```dart
await Posthog().flush();
await Posthog().close();
```

## Setup

### `Posthog.setup`

```dart
Future<void> setup(PostHogConfig config)
```

Initializes the PostHog SDK.

This method sets up the connection to your PostHog instance and prepares
the SDK for tracking events and feature flags.

The `config` object contains your project token, host, and other settings.
To listen for feature flag load events, call onFeatureFlags before this
method.

Repeated setup reapplies Dart-side settings such as the error-tracking
hooks. Most native settings still require close before setup because
the native SDKs ignore repeated setup.

Returns a Future that completes when platform setup has finished.

**Example:**

```dart
final config = PostHogConfig('YOUR_PROJECT_TOKEN');
config.host = 'YOUR_POSTHOG_HOST';
Posthog().onFeatureFlags((loaded) {
  // Feature flags are now loaded, you can read flag values here
});
await Posthog().setup(config);
```

For Android and iOS, if you are performing a manual setup,
ensure `com.posthog.posthog.AUTO_INIT: false` is set in your native
configuration.

## Capture

### `Posthog.capture`

```dart
Future<void> capture({required String eventName, Map<String, Object>? properties, Map<String, Object>? userProperties, Map<String, Object>? userPropertiesSetOnce, Map<String, Object?>? options})
```

Captures a custom event.

Docs: https://posthog.com/docs/product-analytics/user-properties

We recommend using an `[object] [verb]` format for `eventName`, where the
object is the entity that the behavior relates to and the verb is the
behavior itself. For example: `project created`, `user signed up`, or
`invite sent`.

The optional `properties` are event properties.

The optional `userProperties` are person properties set with `$set`.

The optional `userPropertiesSetOnce` are person properties set with
`$set_once`.

The optional `options` tell PostHog how to process this event and are
sent apart from its properties. Known keys:

- `process_person_profile` (`bool`): whether PostHog creates or updates a
  person profile for this event.
- `cookieless_mode` (`bool`): whether PostHog processes this event in
  cookieless mode.
- `disable_skew_correction` (`bool`): whether PostHog keeps the event
  timestamp as sent instead of correcting it for device clock skew.
- `product_tour_id` (`String`): the product tour the event belongs to.

These replace the `$process_person_profile`, `$cookieless_mode`,
`$ignore_sent_at` and `$product_tour_id` properties, and an option wins
over its property. A null value means unset. PostHogConfig.beforeSend
can change them through PostHogEvent.options.

On iOS, macOS, Android, Windows and Linux, other keys are sent
unchanged. On web, the known keys are sent as their legacy properties
and other keys are dropped. On web, posthog-js sets
`$process_person_profile` itself, so `process_person_profile` has no
effect there, and the options of identify, setPersonProperties,
alias and group are dropped because posthog-js sends those events
without event properties.

Returns a Future that completes when the event has been queued.

**Example**

```dart
  await Posthog().capture(
   eventName: 'user_signed_up',
   properties: {
     'login_type': 'email',
     'is_free_trial': true
   }
  );
```

## Identify

### `Posthog.identify`

```dart
Future<void> identify({required String userId, Map<String, Object>? userProperties, Map<String, Object>? userPropertiesSetOnce, Map<String, Object?>? options})
```

Associates events with a specific user.

The `userId` is a unique identifier for your user, typically their email or
database ID.

The optional `userProperties` are person properties set with `$set`.

The optional `userPropertiesSetOnce` are person properties set with
`$set_once`.

The optional `options` tell PostHog how to process the `$identify` or
`$set` event this call sends, as described on capture.

Returns a Future that completes when the identify call has been queued.

Note that identifying a user reloads feature flags, which issues a
`/flags` request even when PostHogConfig.preloadFeatureFlags is `false`.

**Example:**

```dart
await Posthog().identify(
  userId: emailController.text,
  userProperties: {"name": "Peter Griffin", "email": "peter@familyguy.com"},
  userPropertiesSetOnce: {"date_of_first_log_in": "2024-03-01"}
);
```

## Logs

### `Posthog.captureLog`

```dart
Future<void> captureLog({required String body, PostHogLogSeverity level = PostHogLogSeverity.info, Map<String, Object>? attributes, String? traceId, String? spanId, int? traceFlags})
```

Captures a structured log record.

Docs: https://posthog.com/docs/logs

`captureLog` is not gated by remote config.

The `body` is the log message. A blank body is dropped before
PostHogLogsConfig.beforeSend runs.

The optional `level` is the severity, defaulting to
PostHogLogSeverity.info.

The optional `attributes` are per-record attributes (e.g. request id,
duration). Values must be supported by the platform channel serializer.

The optional `traceId`, `spanId`, and `traceFlags` are W3C distributed
tracing fields used to correlate a log with a trace. `traceId` is a
32-character lowercase hex string, `spanId` is 16 characters, and
`traceFlags` is a bitfield whose bit 0 is the `sampled` flag (an explicit
`0` is emitted; `null` omits the field). They pass through unchanged and
are not visible to PostHogLogsConfig.beforeSend.

Auto-captured context (distinct id, session id, screen name, app state,
active feature flags) is added by the native SDK.

Records are passed through PostHogLogsConfig.beforeSend before being
forwarded to the native SDK; a callback may modify or drop them.

Returns a Future that completes when the record has been forwarded.

**Windows/Linux:** not supported.

**Example:**

```dart
await Posthog().captureLog(
  body: 'checkout completed',
  level: PostHogLogSeverity.info,
  attributes: {'order_id': 'ord_789'},
);
```

### `Posthog.logger`

```dart
PostHogLogger get logger
```

Per-level logger facade for capturing structured logs.

Each helper delegates to captureLog with the matching severity. Built
once on first access and cached.

**Example:**

```dart
Posthog().logger.info('user signed in', {'method': 'google'});
Posthog().logger.error('payment failed', {'error_code': 'E001'});
```

## Alias

### `Posthog.alias`

```dart
Future<void> alias({required String alias, Map<String, Object?>? options})
```

Creates an alias for the current user.

Docs:
https://posthog.com/docs/product-analytics/identify#alias-assigning-multiple-distinct-ids-to-the-same-user

The `alias` is the additional distinct ID to associate with the user.

The optional `options` tell PostHog how to process the `$create_alias`
event, as described on capture.

Returns a Future that completes when the alias call has been queued.

## Capture exception

### `Posthog.captureException`

```dart
Future<void> captureException({required Object error, StackTrace? stackTrace, Map<String, Object>? properties, Map<String, Object?>? options})
```

Captures an exception with optional custom properties.

The `error` is the error or exception to capture.

The optional `stackTrace` is attached to the exception. If omitted, the
current stack trace is used by the exception processor where possible.

The optional `properties` are added to the `$exception` event.

The optional `options` tell PostHog how to process the `$exception` event, as described on capture.

Returns a Future that completes when the exception event has been queued.

### `Posthog.captureRunZonedGuardedError`

```dart
Future<void> captureRunZonedGuardedError({required Object error, StackTrace? stackTrace, Map<String, Object>? properties})
```

Captures a `runZonedGuarded` error with optional custom properties.

See: https://api.flutter.dev/flutter/dart-async/runZonedGuarded.html

The `error` is the error or exception received by `runZonedGuarded`.

The optional `stackTrace` is attached to the exception. If omitted, the
current stack trace is used by the exception processor where possible.

The optional `properties` are added to the `$exception` event.

Returns a Future that completes when the exception event has been queued.

## Debug

### `Posthog.debug`

```dart
Future<void> debug(bool enabled)
```

Enables or disables verbose logs about the inner workings of the SDK.

Set `enabled` to `true` to enable debug logs, or `false` to disable them.

Returns a Future that completes when the debug setting has been applied.

## Exception steps

### `Posthog.addExceptionStep`

```dart
Future<void> addExceptionStep(String message, {Map<String, Object>? properties})
```

Records an exception step (breadcrumb-style context record).

Steps accumulate in a rolling, byte-bounded buffer and are attached to
every captured `$exception` event as `$exception_steps`, giving the
PostHog error-tracking UI a timeline of recent activity leading up to each
error. The buffer rotates only by byte-budget eviction (see
PostHogExceptionStepsConfig.maxBytes) and is not cleared by a capture or
an identity change.

The buffer is owned by the embedded native SDK, so steps also survive
native fatal crashes and attach to the crash `$exception` reported on the
next launch.

The `message` is a short, non-empty description of what happened; an empty
or whitespace-only message is ignored. The optional `properties` are
additional context. The reserved keys `$message` and `$timestamp` are
stripped — the SDK sets the canonical values, including a timestamp
captured when the step is recorded.

Recording never throws into your app and does not block the caller.

**Note:**

- Flutter web: forwarded to posthog-js. Steps attach to exceptions
  captured by posthog-js, but not to exceptions captured via
  captureException on web.
- Windows/Linux: the buffer is kept in memory by the Dart
  implementation, and no native crashes are captured on desktop.

**Example:**

```dart
Posthog().addExceptionStep(
  'User tapped Checkout',
  properties: {'screen': 'cart'},
);
```

## Flush

### `Posthog.flush`

```dart
Future<void> flush()
```

Flushes queued events immediately where supported by the platform.

Returns a Future that completes when the flush request has finished.

## Get distinct ID

### `Posthog.getDistinctId`

```dart
Future<String> getDistinctId()
```

Returns the registered `distinctId` property.

Returns an empty string if the platform cannot provide a distinct ID.

## Get feature flag

### `Posthog.getFeatureFlag`

```dart
Future<Object?> getFeatureFlag(String key, {bool? sendFeatureFlagEvent})
```

Returns the feature flag value for `key`.

Returns `null` if the flag does not exist or cannot be loaded. For boolean
flags, returns `true` or `false`. For multivariate flags, returns the
variant key.

`sendFeatureFlagEvent` controls whether this call captures the
`$feature_flag_called` event. Defaults to `null`, which follows
PostHogConfig.sendFeatureFlagEvent. Pass `false` to skip the event for
this call, or `true` to capture it even when the config turns it off.

**Example:**

```dart
final variant = await Posthog().getFeatureFlag('button-color',
    sendFeatureFlagEvent: false);
if (variant == 'red') {
  // show the red button without recording a flag exposure
}
```

## Get feature flag result

### `Posthog.getFeatureFlagResult`

```dart
Future<PostHogFeatureFlagResult?> getFeatureFlagResult(String key, {bool? sendFeatureFlagEvent})
```

Returns the full feature flag result for `key`, including value and
payload.

This is the canonical method for getting feature flag data.
Returns `null` if the flag does not exist or cannot be loaded.

`sendFeatureFlagEvent` controls whether this call captures the
`$feature_flag_called` event. Defaults to `null`, which follows
PostHogConfig.sendFeatureFlagEvent. Pass `false` when you only need the
payload, or `true` to capture the event even when the config turns it off.

**Example:**

```dart
final result = await Posthog().getFeatureFlagResult('my-flag');
if (result != null && result.enabled) {
  final variant = result.variant; // For multivariate flags
  final payload = result.payload; // Associated payload data
}
```

## Get feature flags

### `Posthog.getAllFeatureFlags`

```dart
Future<List<PostHogFeatureFlagResult>?> getAllFeatureFlags()
```

Returns the results of all currently loaded feature flags.

Each PostHogFeatureFlagResult carries the flag's key, enabled state,
variant (for multivariate flags), and payload. This reads the flags from
the last load without a network request; call reloadFeatureFlags first
to refresh them. Unlike getFeatureFlag, it never captures the
`$feature_flag_called` event.

Returns `null` when no flags have been loaded yet or the SDK is disabled.
On web, posthog-js returns an empty list before flags load, and this
returns `null` when the loaded posthog-js predates `getAllFeatureFlags`
(1.395.0).

**Example:**

```dart
final flags = await Posthog().getAllFeatureFlags() ?? [];
for (final flag in flags) {
  print('${flag.key}: ${flag.variant ?? flag.enabled}');
}
```

## Get session ID

### `Posthog.getSessionId`

```dart
Future<String?> getSessionId()
```

Returns the session ID if a session is active.

Returns `null` when no session is active or the platform cannot provide a
session ID.

## Group

### `Posthog.group`

```dart
Future<void> group({required String groupType, required String groupKey, Map<String, Object>? groupProperties, Map<String, Object?>? options})
```

Associates the current user with a group.

Docs: https://posthog.com/docs/product-analytics/group-analytics

The `groupType` is the group type, such as `company`.

The `groupKey` is the unique key for the group.

The optional `groupProperties` are group properties set with `$group_set`.

The optional `options` tell PostHog how to process the `$groupidentify`
event, as described on capture.

Returns a Future that completes when the group call has been queued.

Note that setting a group reloads feature flags, which issues a `/flags`
request even when PostHogConfig.preloadFeatureFlags is `false`.

**Example:**

```dart
await Posthog().group(
 groupType: "company",
 groupKey: "company_id_in_your_db",
 groupProperties: {
   "name": "ACME Corp"
});
```

## Is feature enabled

### `Posthog.isFeatureEnabled`

```dart
Future<bool> isFeatureEnabled(String key, {bool? sendFeatureFlagEvent, bool? defaultValue})
```

Returns whether a boolean feature flag is enabled.

Docs: https://posthog.com/docs/feature-flags and
https://posthog.com/docs/experiments

The `key` is the feature flag key.

`sendFeatureFlagEvent` controls whether this call captures the
`$feature_flag_called` event. Defaults to `null`, which follows
PostHogConfig.sendFeatureFlagEvent. Pass `false` to skip the event for
this call, or `true` to capture it even when the config turns it off.

`defaultValue` is what this call returns when the flag has no value.
Defaults to `null`, which returns `false`. A flag has no value when flags
have not loaded yet, the flags request failed, or no flag has this key. A
flag that has a value always wins, including `false` and variants, and
`$feature_flag_called` never reports `defaultValue` as the flag's value.

Returns `false` when the flag is disabled, and `true` when it is enabled
or set to a variant.

**Example:**

```dart
if (await Posthog().isFeatureEnabled('new-checkout',
    sendFeatureFlagEvent: false)) {
  // show the new checkout without recording a flag exposure
}

// Keep the feature on until the flag says otherwise.
final showCheckout =
    await Posthog().isFeatureEnabled('new-checkout', defaultValue: true);
```

## Is opt out

### `Posthog.isOptOut`

```dart
Future<bool> isOptOut()
```

Returns whether the current user has opted out of data collection.

## Is session replay active

### `Posthog.isSessionReplayActive`

```dart
Future<bool> isSessionReplayActive()
```

Returns whether session replay is currently active.

Returns `false` when session replay is inactive or unsupported by the
current platform.

**Windows/Linux:** not supported.

## Opt in

### `Posthog.optIn`

```dart
Future<void> optIn()
```

Opts the current user back in to data collection.

Reinstalls Flutter error autocapture. If optOut stopped session replay,
this starts a new recording.

Returns a Future that completes when the opt-in request has been queued.

## Register

### `Posthog.register`

```dart
Future<void> register(String key, Object value)
```

Registers a super property sent with all following events.

The property remains active until unregister is called with the same
`key`. The `value` must be supported by the platform channel serializer.

Returns a Future that completes when the property has been registered.

## Reload feature flags

### `Posthog.reloadFeatureFlags`

```dart
Future<PostHogFeatureFlagsLoaded> reloadFeatureFlags()
```

Reloads feature flags for the current user.

Returns a Future that completes when the reload finishes, with the
enabled flags and whether loading failed. When it failed,
PostHogFeatureFlagsLoaded.errorsLoading is `true` and the flags are the
last known values.

**Flutter web:** with posthog-js 1.438.2 or later, completes once this
reload's request settles; if posthog-js skips it (flags disabled,
reloading paused, or after repeated network failures), it completes right
away with the current flags and `errorsLoading: true`. Older posthog-js
completes with the next flags it reports, and when it skips the request,
with `errorsLoading: true` once every request attempt posthog-js may
make could have timed out: `feature_flag_request_max_retries + 2` times
its `feature_flag_request_timeout_ms`, plus 500 ms per retry (9.5 s with
the defaults; right away when flags are disabled).

**Example:**

```dart
final loaded = await Posthog().reloadFeatureFlags();
if (!loaded.errorsLoading && loaded.flags.contains('new-checkout')) {
  // The flag is enabled.
}
```

## Reset

### `Posthog.reset`

```dart
Future<void> reset()
```

Resets all cached properties including the `distinctId`.

The SDK will behave as if it has been setup for the first time.

Returns a Future that completes when the reset request has been queued.

## Reset group properties for flags

### `Posthog.resetGroupPropertiesForFlags`

```dart
Future<void> resetGroupPropertiesForFlags({String? groupType, bool reloadFeatureFlags = true})
```

Clears group properties that were set for feature flag evaluation via
setGroupPropertiesForFlags.

If `groupType` is provided, only properties for that group type are
cleared; otherwise all group properties are cleared.

Set `reloadFeatureFlags` to `false` to skip reloading flags after clearing
the properties (defaults to `true`). When `true`, the returned Future
awaits the reload before completing. On web, see
Posthog.reloadFeatureFlags for which posthog-js versions wait for it.

## Reset person properties for flags

### `Posthog.resetPersonPropertiesForFlags`

```dart
Future<void> resetPersonPropertiesForFlags({bool reloadFeatureFlags = true})
```

Clears all person properties that were set for feature flag evaluation via
setPersonPropertiesForFlags.

Set `reloadFeatureFlags` to `false` to skip reloading flags after clearing
the properties (defaults to `true`). When `true`, the returned Future
awaits the reload before completing. On web, see
Posthog.reloadFeatureFlags for which posthog-js versions wait for it.

## Screen

### `Posthog.screen`

```dart
Future<void> screen({required String screenName, Map<String, Object>? properties, Map<String, Object?>? options})
```

Captures a screen view event.

The `screenName` is the screen title or route name.

The optional `properties` are additional screen event properties.

The optional `options` tell PostHog how to process the `$screen` event, as described on capture.

Returns a Future that completes when the screen event has been queued.

## Set group properties for flags

### `Posthog.setGroupPropertiesForFlags`

```dart
Future<void> setGroupPropertiesForFlags(String groupType, Map<String, Object> groupProperties, {bool reloadFeatureFlags = true})
```

Sets properties for a specific `groupType` that are used only for feature
flag evaluation.

The properties are sent inline with the next feature flag evaluation
request, so flags that target group properties can be evaluated without
waiting for ingestion.

The `groupProperties` are merged with any previously set values for the
same `groupType`; matching keys are overwritten. If `groupProperties` is
empty, this is a no-op.

Set `reloadFeatureFlags` to `false` to skip reloading flags after updating
the properties (defaults to `true`). When `true`, the returned Future
awaits the reload before completing. On web, see
Posthog.reloadFeatureFlags for which posthog-js versions wait for it.

**Example:**

```dart
await Posthog().setGroupPropertiesForFlags(
  "organization",
  {"name": "ACME Corp", "is_enterprise": true},
);
```

## Set person properties

### `Posthog.setPersonProperties`

```dart
Future<void> setPersonProperties({Map<String, Object>? userPropertiesToSet, Map<String, Object>? userPropertiesToSetOnce, Map<String, Object?>? options})
```

Sets person properties for the current user without requiring identify.

This method sends person property updates without changing the current
distinct ID.

The optional `userPropertiesToSet` values are set with `$set` and overwrite
existing values.

The optional `userPropertiesToSetOnce` values are set with `$set_once` and
do not overwrite existing values.

The optional `options` tell PostHog how to process the `$set` event this
call sends, as described on capture.

Returns a Future that completes when the update has been queued.
If both property maps are null or empty, no event is queued.

**Example:**

```dart
await Posthog().setPersonProperties(
  userPropertiesToSet: {"name": "John Doe", "email": "john@example.com"},
  userPropertiesToSetOnce: {"date_of_first_login": "2024-03-01"}
);
```

## Set person properties for flags

### `Posthog.setPersonPropertiesForFlags`

```dart
Future<void> setPersonPropertiesForFlags(Map<String, Object> userProperties, {bool reloadFeatureFlags = true})
```

Sets person properties that are used only for feature flag evaluation.

Docs: https://posthog.com/docs/feature-flags

Unlike setPersonProperties, this does **not** enqueue a `$set` event. The
properties are sent inline with the next feature flag evaluation request,
so flags that target these properties can be evaluated immediately without
waiting for the `$set` event to be ingested into the person store.

The `userProperties` are merged with any previously set values; matching
keys are overwritten. If `userProperties` is empty, this is a no-op.

Set `reloadFeatureFlags` to `false` to skip reloading flags after updating
the properties (defaults to `true`). When `true`, the returned Future
awaits the reload before completing, so the next getFeatureFlag /
getFeatureFlagResult reflects the updated properties. On web, see
Posthog.reloadFeatureFlags for which posthog-js versions wait for it.

**Example:**

```dart
await Posthog().setPersonPropertiesForFlags({
  "storefront_country": "US",
  "superwall_demand_score": 88,
});
final result = await Posthog().getFeatureFlagResult("my_flag");
```

## Shutdown

### `Posthog.close`

```dart
Future<void> close()
```

Closes the PostHog SDK and cleans up resources.

This is also the entry point for reconfiguring: the native SDKs ignore a
repeated setup, so changing the project token, host, or native session
replay settings means calling close first and then setup again.

Whatever session replay records after the next setup starts as a fresh
recording. Whether the platform also changes the *session* here differs by
platform, so do not rely on a close/setup pair rotating the session id.

Returns a Future that completes when platform resources have been closed.

**Windows/Linux:** first makes one attempt to send the queued events and
waits for it for up to two seconds, and for the queue's files for up to
two more. Events left unsent go out with the next setup, or are lost
when the application support directory is unavailable and state is kept
in memory.

**Note:** After calling `close()`, surveys will not be rendered until the
SDK is re-initialized and the next navigation event occurs.

## Start session recording

### `Posthog.startSessionRecording`

```dart
Future<void> startSessionRecording({bool resumeCurrent = true})
```

Starts session recording.

This method will have no effect if PostHog is not enabled, or if session
replay is disabled in your project settings.

Set `resumeCurrent` to `true` (the default) to resume recording the current
session. Set it to `false` to start a new session and begin recording —
though a new session is not guaranteed while recording is already active,
so call stopSessionRecording first if you need one. Either way, `false`
restarts the recording even when the platform keeps the current session id.

Returns a Future that completes when the start request has been sent.

**Windows/Linux:** not supported.

## Stop session recording

### `Posthog.stopSessionRecording`

```dart
Future<void> stopSessionRecording()
```

Stops the current session recording if one is in progress.

This method will have no effect if PostHog is not enabled.

Returns a Future that completes when the stop request has been sent.

**Windows/Linux:** not supported.

## Unregister

### `Posthog.unregister`

```dart
Future<void> unregister(String key)
```

Unregisters a previously registered super property.

The `key` identifies the property to stop sending with future events.

Returns a Future that completes when the property has been removed.

## SDK utils

### `Posthog.Posthog.new`

```dart
Posthog()
```

Returns the singleton PostHog client instance.

### `Posthog.captureAi`

```dart
Future<String?> captureAi({required String eventName, Map<String, Object>? properties, Map<String, Object>? userProperties, Map<String, Object>? userPropertiesSetOnce, Map<String, Object?>? options})
```

Captures an AI observability event, such as `$ai_generation`,
`$ai_span`, `$ai_trace` or `$ai_embedding`, and sends it to PostHog's AI
endpoint, which accepts much larger events than capture.

Takes the same arguments as capture and goes through the same
PostHogConfig.beforeSend callbacks. The event is queued separately from
other events and sent unchanged: the SDK doesn't redact or truncate
prompts, outputs or media. PostHog drops an event sent here whose name
doesn't start with `$ai_`. capture never sends events here, even ones
named `$ai_*`.

Returns the event's UUID once the SDK has admitted it to the AI queue.
`null` means the event was not admitted and will not be sent:

- a PostHogConfig.beforeSend callback dropped it,
- it is over PostHogConfig.captureAiMaxEventBytes,
- the SDK is disabled, not set up or opted out, or
- the platform is web (see below).

**Platforms:** supported on iOS, macOS, Android, Windows and Linux. On
web, `captureAi` is a no-op: it sends nothing, logs a debug message and
returns `null`.

**Example**

```dart
  await Posthog().captureAi(
    eventName: r'$ai_generation',
    properties: {
      r'$ai_trace_id': traceId,
      r'$ai_model': 'gpt-4o',
      r'$ai_provider': 'openai',
    },
  );
```

### `Posthog.captureFeatureInteraction`

```dart
Future<void> captureFeatureInteraction(String flag, {String? flagVariant})
```

Captures a `$feature_interaction` event when the user interacts with the
feature behind the feature flag `flag`.

The event carries `feature_flag` and, for multivariate flags,
`feature_flag_variant`, and sets the person property
`$feature_interaction/<flag>` to the variant.

`flagVariant` defaults to `null`, which uses the flag's current value
without capturing `$feature_flag_called`. When the flag has no value
(not loaded or unknown), Android falls back to `true`, while iOS, macOS,
web, Windows, and Linux skip the event.

**Example:**

```dart
ElevatedButton(
  onPressed: () => Posthog().captureFeatureInteraction('new-checkout'),
  child: const Text('Checkout'),
);
```

### `Posthog.captureFeatureView`

```dart
Future<void> captureFeatureView(String flag, {String? flagVariant})
```

Captures a `$feature_view` event when the user sees the feature behind
the feature flag `flag`.

The event carries `feature_flag` and, for multivariate flags,
`feature_flag_variant`, and sets the person property
`$feature_view/<flag>` to the variant.

`flagVariant` defaults to `null`, which uses the flag's current value
without capturing `$feature_flag_called`. When the flag has no value
(not loaded or unknown), Android falls back to `true`, while iOS, macOS,
web, Windows, and Linux skip the event.

**Example:**

```dart
await Posthog().captureFeatureView('new-checkout');
await Posthog().captureFeatureView('button-color', flagVariant: 'red');
```

### `Posthog.capturePushNotificationOpened`

```dart
Future<void> capturePushNotificationOpened({String? title, String? subtitle, String? body, Map<String, Object?>? payload, String? action})
```

Captures `$push_notification_opened` when a user opens a push
notification.

Call this only for opens PostHogConfig.capturePushNotificationOpened
cannot see itself — local notifications on either platform, notifications
you display yourself from a foreground message, and push delivered outside
FCM on Android. That doc has the full coverage matrix.

Do not wire this to `FirebaseMessaging.onMessageOpenedApp` or
`getInitialMessage()`: the SDK already captures those taps. On both
platforms a second report of a PostHog-sent notification within 5 minutes
of the first is skipped; an open of a push PostHog did not send carries
nothing to match on, so it is counted twice.

That dedupe also means a manual call cannot enrich an automatic capture.
The Android tray intent carries no notification text, so its automatic
event has no `$notification_title` or `$notification_body`, and
re-reporting the tap with them is skipped rather than merged.

```dart
// A notification you built and displayed yourself.
Posthog().capturePushNotificationOpened(
  title: 'Your order shipped',
  body: 'Track it in the app',
  payload: {'order_id': '1234'},
);
```

The event is built natively, so PostHogConfig.beforeSend callbacks do
not run on it — redact anything sensitive before passing it here.

Keys of `payload`'s `posthog` entry become `$notification_<key>`
properties; it is decoded natively whether it arrives as a map or as a
JSON string. Leave `action` `null` for a plain tap — only action-button
taps carry an identifier.

`subtitle` is iOS only and ignored on Android, which has no such field.

Not supported on Flutter web, Windows or Linux.

### `Posthog.onFeatureFlags`

```dart
PostHogFeatureFlagsSubscription onFeatureFlags(OnFeatureFlagsCallback callback)
```

Registers a `callback` that's invoked whenever feature flags are loaded
or updated.

It's invoked after the SDK loads flags at startup (including from
bootstrap values), after reloadFeatureFlags, and after calls that
reload flags such as identify, group or reset. If a load fails,
PostHogFeatureFlagsLoaded.errorsLoading is `true` and the values are
the last known flags. If flags have already loaded when you register,
it's also invoked with the current values shortly afterwards.

You can register before setup, even before
`WidgetsFlutterBinding.ensureInitialized()`, and the callback stays
registered across close and setup. Treat each invocation as "flags may have
changed", not as an exactly-once event.

Returns a subscription; call
PostHogFeatureFlagsSubscription.unsubscribe to stop receiving updates.

**Example:**

```dart
final subscription = Posthog().onFeatureFlags((loaded) {
  if (loaded.variants['new-checkout'] == 'test') {
    // Show the test variant.
  }
});

// Later, stop listening.
subscription.unsubscribe();
```

### `Posthog.optOut`

```dart
Future<void> optOut()
```

Opts the current user out of data collection.

Also stops session replay and uninstalls Flutter error autocapture.

Returns a Future that completes when the opt-out request has been queued.

### `Posthog.registerPushNotificationToken`

```dart
Future<void> registerPushNotificationToken(String deviceToken, {String? appId})
```

Registers this device's push token or Firebase Installation ID (FID) so
PostHog Workflows can target it.

Both platforms register automatically at startup when
PostHogConfig.capturePushNotificationSubscriptions is enabled, so the
main reason to call this is a later Firebase registration or token refresh,
which that startup fetch cannot see.

`appId` identifies the app the identifier belongs to: the Firebase
`project_id` for an FCM token or FID, the APNs bundle id for an APNs token.
It tells PostHog which provider to deliver through — the platform is
only recorded alongside it. Leave it `null` and iOS falls back to the
bundle id while Android falls back to the default `FirebaseApp`'s project
id, so pass it explicitly if your app does not use Firebase or registers
for a non-default Firebase project. Android cannot register without one
and reports the skip as a `PlatformException`, logged in debug builds.

**The default is APNs on iOS and FCM on Android**, matching what
PostHogConfig.capturePushNotificationSubscriptions registers on its own.
On Android, enabling `firebase_messaging_installation_id_enabled` in the
app's manifest switches automatic registration to FIDs. Pass the FID to
this method unchanged; no identifier type parameter is needed.

With `firebase_messaging` 17+, enable that manifest flag and forward
`onRegistered` after setup completes, then register with Firebase:

```dart
if (Platform.isAndroid) {
  FirebaseMessaging.instance.onRegistered.listen(
    (fid) => Posthog().registerPushNotificationToken(fid),
  );
  await FirebaseMessaging.instance.register();
}
```

On Android, explicit calls refresh the subscription even when the FID
hasn't changed; automatic startup registration still deduplicates it.
For older `firebase_messaging` versions, forward `onTokenRefresh` instead
and leave FID mode disabled. Neither Firebase callback should be forwarded
unguarded on iOS: pairing a Firebase identifier with the default APNs
bundle id causes delivery to fail.

**Using FCM on both platforms** is supported — pass the Firebase
`project_id` as `appId` on iOS too — but you must set
PostHogConfig.capturePushNotificationSubscriptions to `false` first.
PostHog stores one subscription per app id, so leaving automatic
registration on gives an iOS device two: an APNs one under the bundle id
and an FCM one under the project id. A Workflow configured with both
integrations then delivers to that device twice, and
unregisterPushNotificationToken only clears the most recently registered
of the two.

Registration also fails server-side if your PostHog project has no
Firebase or APNs integration configured for `appId`.

Call this only after setup has completed: the native SDKs silently drop
a token registered before they are initialized, and this method still
completes without an error.

Not supported on Flutter web, macOS, Windows or Linux.

### `Posthog.setAppLanguage`

```dart
Future<void> setAppLanguage(String? language)
```

Sets the `$app_language` property: the language your app displays, sent
with every event.

Default: PosthogObserver reports the locale your `MaterialApp` resolved
each time a route changes, which is `en-US` if you declare no
`supportedLocales`. Call this if you don't use the observer, translate
outside `Localizations`, or want to report a different value.

Your value wins over the observer's and survives reset. It's kept in
memory, so call it again on the next launch. Compare `$locale`, which is
the device language, or on iOS and macOS a language picked for the app in
Settings.

The `language` is a BCP 47 tag, such as `de` or `pt-BR`. Pass `null` to go
back to the observer's value.

**Example:**

```dart
await Posthog().setAppLanguage('de');
```

### `Posthog.unregisterPushNotificationToken`

```dart
Future<void> unregisterPushNotificationToken()
```

Unregisters this device's push token so Workflows stop targeting it — for
example from your logout flow.

The intent is durable: if the request fails or the device is offline, the
native SDK retries it on the next flush or app launch. reset already
moves a registered token to the new anonymous identity on its own, so this
is only needed when you manage subscriptions yourself.

Not supported on Flutter web, macOS, Windows or Linux.

## PostHogIsolateExtension

### `PostHogIsolateExtension`

```dart
extension PostHogIsolateExtension
```

Forwards uncaught errors from an isolate to PostHog.

#### `PostHogIsolateExtension.addPostHogErrorListener`

```dart
RawReceivePort addPostHogErrorListener()
```

Captures this isolate's uncaught errors using Posthog.captureException.

Call from the main isolate after initializing PostHog. This does not
require `errorTrackingConfig.captureIsolateErrors` to be enabled.
Errors are reported as unhandled, with the background stack trace and
this isolate's debug name. Dart supplies the error as a string, not the
original exception object.

Spawn the isolate paused, add the listener, then resume it to avoid
missing errors before the listener is registered:

```dart
final isolate = await Isolate.spawn(worker, message, paused: true);
final listener = isolate.addPostHogErrorListener();
isolate.resume(isolate.pauseCapability!);
```

Returns the listener port. Pass it to removePostHogErrorListener to
stop forwarding and close the port. The listener is also removed and
its port closed automatically when this isolate exits.
Existing error listeners and fatal-error behavior are unchanged.
Each call installs a separate listener, so call only once per isolate.

Not supported on Flutter web, which has no isolates.

#### `PostHogIsolateExtension.removePostHogErrorListener`

```dart
void removePostHogErrorListener(RawReceivePort listener)
```

Stops forwarding errors and closes the listener's port.

Pass the `listener` returned by addPostHogErrorListener on this isolate.
Removes both the error listener and its automatic exit-cleanup listener.
Calling this again, including after the isolate exits, is safe.

## PostHogLogger

### `PostHogLogger`

```dart
class PostHogLogger
```

Per-level convenience facade for capturing structured logs.

Obtain it via `Posthog().logger`. Each helper captures a record at its
severity and is equivalent to calling `Posthog().captureLog(...)` with the
matching `level`.

**Example:**

```dart
Posthog().logger.info('checkout completed', {'order_id': 'ord_789'});
Posthog().logger.error('payment failed', {'error_code': 'E001'});
```

#### `PostHogLogger.debug`

```dart
Future<void> debug(String body, [Map<String, Object>? attributes ])
```

Captures a PostHogLogSeverity.debug record.

#### `PostHogLogger.error`

```dart
Future<void> error(String body, [Map<String, Object>? attributes ])
```

Captures a PostHogLogSeverity.error record.

#### `PostHogLogger.fatal`

```dart
Future<void> fatal(String body, [Map<String, Object>? attributes ])
```

Captures a PostHogLogSeverity.fatal record.

#### `PostHogLogger.info`

```dart
Future<void> info(String body, [Map<String, Object>? attributes ])
```

Captures a PostHogLogSeverity.info record.

#### `PostHogLogger.trace`

```dart
Future<void> trace(String body, [Map<String, Object>? attributes ])
```

Captures a PostHogLogSeverity.trace record.

#### `PostHogLogger.warn`

```dart
Future<void> warn(String body, [Map<String, Object>? attributes ])
```

Captures a PostHogLogSeverity.warn record.

## PostHogMaskWidget

### `PostHogMaskWidget`

```dart
class PostHogMaskWidget
```

Masks a widget subtree in PostHog session replay snapshots.

Wrap sensitive UI with PostHogMaskWidget to hide that area in captured
screenshots, regardless of the global session replay masking settings.
`PostHogUnmaskWidget` overrides this mask in either nesting order, except
for sensitive text inputs. See that widget's documentation for geometry
limits when revealing part of an enclosing mask.

**Flutter web:** the canvas is masked by posthog-js rather than by this
plugin, so the first PostHogMaskWidget or `PostHogUnmaskWidget` to mount
turns canvas masking on —
which restarts an in-flight recording once, because masking also excludes
the Flutter semantics DOM tree via `blockSelector`, and posthog-js only
reads that when recording starts. Canvas recording itself must be enabled
separately — either with `captureCanvas: { recordCanvas: true }` as shown
below, or with the canvas capture toggle in your project's session replay
settings. Frames captured before that first mount are recorded unmasked;
to cover the window between `posthog.init` and Flutter booting, declare
`session_recording: { captureCanvas: { recordCanvas: true }, canvasCapture: { maskRegionsFn: () => null } }`
in your `posthog.init` call — until this plugin takes over, those frames are
skipped instead of recorded. Your app must be wrapped in `PostHogWidget`,
and every mask/unmask widget must sit inside it — otherwise canvas frames
are skipped instead of recorded unmasked, until the mask widget is moved
inside `PostHogWidget` or removed. iOS and Android need no setup either
way.

#### `PostHogMaskWidget()`

```dart
const PostHogMaskWidget({Key? key, required Widget child})
```

Creates a mask around `child` for session replay.

#### `<></>`

```dart
Widget child
```

The widget subtree to mask in session replay snapshots.

## PostHogPlatformView

### `PostHogPlatformView`

```dart
class PostHogPlatformView
```

Session replay policy marker for an embedded platform view.

Wrap a platform view (e.g. `WebViewWidget`, `GoogleMap`) to override the
global PostHogSessionReplayConfig.maskAllPlatformViews setting for that
specific view.

The privacy policy applies to **every** platform view in the wrapped
subtree, not just the nearest one. Wrapping a container that embeds several
platform views in `privacy: capture` reveals all of them. A nested
PostHogPlatformView overrides the inherited policy for its own subtree.

```dart
PostHogPlatformView(
  privacy: PostHogPlatformViewPrivacy.capture,
  child: WebViewWidget(controller: _controller),
)
```

This widget has no runtime state — it is a pure marker. The compositor reads
privacy from the element tree during each capture frame.

#### `PostHogPlatformView()`

```dart
const PostHogPlatformView({Key? key, required Widget child, PostHogPlatformViewPrivacy privacy = PostHogPlatformViewPrivacy.mask})
```

Creates a session replay policy marker around `child`.

#### `<></>`

```dart
Widget child
```

The platform view subtree this policy applies to.

#### `<></>`

```dart
PostHogPlatformViewPrivacy privacy
```

How the platform views in child are handled in session replay.

Defaults to PostHogPlatformViewPrivacy.mask.

## PostHogUnmaskWidget

### `PostHogUnmaskWidget`

```dart
class PostHogUnmaskWidget
```

Reveals a widget subtree in session replay despite global text/image masking.

Keep `maskAllTexts` / `maskAllImages` enabled and reveal only known-safe UI:

```dart
PostHogUnmaskWidget(child: Text('Try again'))
```

Only wrap content known to be safe. This overrides global masking and
`PostHogMaskWidget` in either nesting order, but sensitive text inputs always
remain masked. Masks on overlapping sibling widgets are not removed.

For an enclosing mask, only the visible rectangular unmask region is
excluded. If its transform relative to that mask is not axis-aligned, or a
non-rectangular/custom clip prevents a safe exclusion, the enclosing mask is
retained. Web masks use conservative bounds and can cover the edges of an
unmasked region. Native platform views and captured native screens are
unaffected.

On Flutter web, mounting either this widget or `PostHogMaskWidget` enables
canvas masking and restarts an in-flight recording once to protect the
semantics DOM too. Canvas recording must be enabled separately. Frames
captured before the first mount are not protected by this opt-in. Declare
`session_recording: { canvasCapture: { maskRegionsFn: () => null } }` in
`posthog.init` to skip those frames until Flutter installs its mask provider.
Keep both kinds of wrapper inside `PostHogWidget` on all platforms. On web,
a mounted wrapper outside the tracked tree causes frames to be skipped once
masking is enabled, until it is moved inside or removed.

#### `PostHogUnmaskWidget()`

```dart
const PostHogUnmaskWidget({Key? key, required Widget child})
```

Creates an exception to global text/image masking around `child`.

#### `<></>`

```dart
Widget child
```

The known-safe widget subtree to reveal in session replay.

## PostHogWidget

### `PostHogWidget`

```dart
class PostHogWidget
```

Wraps a Flutter app to enable mobile session replay screenshots.

Place PostHogWidget above your app content when `PostHogConfig.sessionReplay`
is enabled. The widget captures snapshots from child and sends them to the
native SDK while session recording is active.

#### `PostHogWidget()`

```dart
const PostHogWidget({Key? key, required Widget child})
```

Creates a session replay root widget around `child`.

#### `<></>`

```dart
Widget child
```

The widget subtree to include in session replay snapshots.

## PosthogObserver

### `PosthogObserver`

```dart
class PosthogObserver
```

A Flutter NavigatorObserver that automatically captures `$screen` events.

Add this observer to `MaterialApp.navigatorObservers` or a router such as
`go_router` to capture screen views when named routes are pushed, popped, or
replaced.

#### `PosthogObserver()`

```dart
PosthogObserver({ScreenNameExtractor nameExtractor = defaultNameExtractor, PostHogRouteFilter routeFilter = defaultPostHogRouteFilter})
```

Creates a PostHog route observer.

The `nameExtractor` reads a screen name from route settings. It defaults
to defaultNameExtractor, which returns RouteSettings.name.

The `routeFilter` determines which routes are eligible for tracking. It
defaults to defaultPostHogRouteFilter, which tracks PageRoutes.

Screen events are only sent while the app is in the foreground.

## Types

### `BeforeSendCallback`

```dart
BeforeSendCallback = PostHogEvent? Function(PostHogEvent event)
```

Callback to intercept and modify events before they are sent to PostHog.

The `event` argument contains the event name and user-provided properties
that are about to be captured. Return a possibly modified event to send it,
or return `null` to drop it.

Callbacks are synchronous, as in the native SDKs, so the event is sent
with the user and properties it was captured under.

### `BeforeSendLogCallback`

```dart
BeforeSendLogCallback = PostHogLogRecord? Function(PostHogLogRecord record)
```

Callback to intercept and modify log records before they are sent to
PostHog.

The `record` argument contains the body, level, and user-provided
attributes that are about to be captured. Return a possibly modified record
to send it, or return `null` to drop it.

Callbacks are synchronous, as in the native SDKs.

### `PostHogBootstrapConfig`

```dart
class PostHogBootstrapConfig
```

Pre-seeded identity and feature-flag state applied on the very first SDK
launch, before any network request completes.

Assign an instance to PostHogConfig.bootstrap before calling
`Posthog().setup(config)`. The values are forwarded to the native iOS/Android
SDKs, which own all bootstrap behavior:

- Bootstrapped identity seeds the very first session only. It is applied only
  when no identity is persisted for that scope, and never overwrites an
  existing user. An anonymous bootstrap (isIdentifiedId `false`) seeds the
  anonymous id; an identified bootstrap (isIdentifiedId `true`) seeds the
  distinct id and marks the user identified (merging an existing anonymous
  user via `identify()`, or preserving a different identified user with a
  warning) — it never becomes the device id.
- Only enabled bootstrapped flags are served (a `true` or a non-empty
  variant string; `false` or empty values are dropped). They are served
  until the first `/flags` response, which then takes over, and they are
  dropped on `reset()`.

**Flutter web:** not applied. Configure `bootstrap` in your
`posthog.init({...})` call instead.

#### `PostHogBootstrapConfig()`

```dart
const PostHogBootstrapConfig({String? distinctId, bool isIdentifiedId = false, Map<String, Object>? featureFlags, Map<String, Object?>? featureFlagPayloads})
```

Creates a bootstrap configuration.

Pass only the dimensions you want to seed; leave the rest `null`.

#### `<></>`

```dart
String? distinctId
```

The distinct id to seed on first launch.

When isIdentifiedId is `false` (the default) this becomes the anonymous
id — the `$distinct_id` on pre-identify events. When `true` it is treated
as an already-identified user's distinct id.

#### `<></>`

```dart
Map<String, Object?>? featureFlagPayloads
```

JSON payloads paired with featureFlags, keyed by flag key. Each value is
the already-decoded payload (map, list, string, number, `null`, ...).

#### `<></>`

```dart
Map<String, Object>? featureFlags
```

Feature flag values served until the first `/flags` response arrives,
keyed by flag key. Each value is a `bool` for boolean flags or a `String`
for multivariate flags. Only enabled values are served: `false` or an
empty string is dropped.

#### `<></>`

```dart
bool isIdentifiedId
```

Whether distinctId represents an already-identified user.

Defaults to `false`. Set to `true` when the host application resolved the
user's identity outside the SDK (for example from a backend session token).

### `PostHogCompression`

```dart
enum PostHogCompression
```

Controls how the SDK compresses request bodies before sending them to the
PostHog API.

##### Values

- `gzip`: Gzip request bodies.
- `none`: Send request bodies uncompressed.

### `PostHogConfig`

```dart
class PostHogConfig
```

Configuration used to initialize the PostHog Flutter SDK.

Create an instance with your project token, customize any options, and pass
it to `Posthog().setup(config)`.

#### `PostHogConfig()`

```dart
PostHogConfig(String projectToken, {List<BeforeSendCallback>? beforeSend})
```

Creates a configuration for `projectToken`.

The `projectToken` is trimmed before it is stored.

The optional `beforeSend` callbacks are copied into `beforeSend` and run in
order before Dart-captured events are sent.

#### `<></>`

```dart
List<BeforeSendCallback> beforeSend
```

Callbacks to intercept and modify events before they are sent to PostHog.

Callbacks are invoked in order for events captured via Dart APIs:

- `Posthog().capture()` - custom events
- `Posthog().screen()` - screen events (event name will be `$screen`)
- `Posthog().captureException()` - exception events (event name will be
  `$exception`)

Each callback receives the event (possibly modified by previous callbacks).
Return a possibly modified event to continue, or return `null` to drop it.

**Example (single callback):**

```dart
config.beforeSend = [(event) {
  // Drop specific events
  if (event.event == 'sensitive_event') {
    return null;
  }
  return event;
}];
```

**Example (multiple callbacks):**

```dart
config.beforeSend = [
  // First: PII redaction
  (event) {
    event.properties?.remove('email');
    return event;
  },
  // Second: Event filtering
  (event) => event.event == 'drop me' ? null : event,
];
```

**Limitations:**

- These callbacks do NOT intercept native-initiated events such as:
  - Session replay events (`$snapshot`) when `config.sessionReplay` is
    enabled
  - Application lifecycle events (`Application Opened`, etc.) when
    `config.captureApplicationLifecycleEvents` is enabled
  - Feature flag events (`$feature_flag_called`) when
    `config.sendFeatureFlagEvent` is enabled
  - Identity events (`$identify`, `$set`, `$create_alias`,
    `$groupidentify`) from `identify`, `setPersonProperties`, `alias`
    and `group`
  - Survey events (`survey shown`, etc.) when `config.surveys` is enabled
    On iOS, macOS and Android, add a native hook with
    `PosthogFlutterPlugin.addBeforeSend` (Swift or Kotlin) to filter or
    edit those events.
- On iOS, macOS, Android, Windows and Linux, the callbacks see the
  system properties (like `$device_type` and `$session_id`), the
  registered properties and the options the SDK adds, and can change
  them for that event, except `$lib` and `$lib_version`, which PostHog
  sets from the SDK. On iOS, macOS and Android, registering callbacks
  adds one more call to the native SDK per event. The native SDK keeps
  each built event until Dart sends it back, and discards one still
  waiting after a minute (for example, after a hot restart). On web,
  only the event's own properties are available; posthog-js adds the
  rest later.

**Note:**

- Callbacks are synchronous and run on the calling isolate, so a slow one
  blocks the UI. Load anything they need (such as remote config or feature
  flags) ahead of time; a change made after the callback returns is not
  sent.
- A callback that captures an event must not do so for that event too, or
  it never finishes.
- On web, an event whose callback calls `reset()` stays on its user but
  joins the next user's session and person processing, and its user
  properties are dropped, because posthog-js builds the event after the
  callbacks.
- If a callback throws, the event is dropped and later callbacks are not
  called.
- If any callback returns `null`, the event is dropped and subsequent
  callbacks are not called.

#### `<></>`

```dart
PostHogBootstrapConfig? bootstrap
```

Pre-seeded identity and feature-flag state applied on the very first SDK
launch, before any network request completes.

Set this before calling `Posthog().setup(config)` so events captured during
cold start carry a caller-controlled `$distinct_id` and feature-flag reads
return caller-provided values before the first `/flags` response. Mirrors
the `bootstrap` option in `posthog-js`.

Forwarded to the native iOS/Android SDKs, and on Windows/Linux to the
pure-Dart implementation, which apply all precedence rules (never
overwrite persisted identity, overlay loaded flags over bootstrapped ones,
drop the bootstrap on `reset()`). Defaults to `null` (no bootstrap).

**Flutter web:** not applied. The web SDK hooks onto an already-initialized
posthog-js instance, so configure `bootstrap` in your `posthog.init({...})`
call instead.

#### `<></>`

```dart
PostHogCompression? captureAiCompression
```

How Posthog.captureAi request bodies are compressed, separately from
compression.

Not applied on web, where Posthog.captureAi sends nothing.

Defaults to `null`, which keeps the SDK default (gzip).

#### `<></>`

```dart
int? captureAiMaxEventBytes
```

Maximum size, in bytes, of a Posthog.captureAi event. The SDK drops a
larger event and Posthog.captureAi returns `null`.

Use it to lower the limit. PostHog drops AI events whose properties are
over 8 MiB, so a larger value, or a value of `0` or less, uses the
default. By default the SDK drops a serialized event over 8 MiB plus
64 KiB for the rest of the event, measured before compression. A set
value limits the whole serialized event.

Not applied on web, where Posthog.captureAi sends nothing.

Defaults to `null`, which keeps the SDK default.

#### `<></>`

```dart
int? captureAiMaxQueueSize
```

Maximum number of Posthog.captureAi events kept in their on-disk queue
before the oldest are dropped.

AI events can be megabytes, so the default (100) is lower than
maxQueueSize. The queue also keeps at most 50 MiB of AI events,
whatever this is set to. A value of `0` or less uses the default.

When it is full, the oldest events are dropped.

Not applied on web, where Posthog.captureAi sends nothing.

Defaults to `null`, which keeps the SDK default.

#### `<></>`

```dart
Duration? captureAiTimeout
```

Timeout of a Posthog.captureAi request: how long it may go without
network activity. On iOS, macOS and Android it is sent to the native SDK
in whole seconds (a positive value under one second is sent as one
second).

AI requests can carry several MB, so the default (60 seconds) is
longer than for other requests. Duration.zero or less uses the
default.

Not applied on web, where Posthog.captureAi sends nothing.

Defaults to `null`, which keeps the SDK default.

#### `<></>`

```dart
bool captureApplicationLifecycleEvents
```

Whether the SDK captures application lifecycle events automatically.

Captured events include app opened, backgrounded, installed, and updated
events where supported by the platform. Defaults to `true`.

#### `<></>`

```dart
bool capturePushNotificationOpened
```

Whether to automatically capture `$push_notification_opened` when a user
taps a PostHog-delivered notification.

Every tap on a **remote** notification is captured on both platforms,
whether it cold-launched the app or the app was already running.
Locally-scheduled notifications are ignored. On Android a tap is
recognised by the `google.message_id` extra Firebase puts on the intent,
so push delivered outside FCM is not seen. Call
Posthog.capturePushNotificationOpened for the opens this misses.

**Flutter web, Windows and Linux:** not supported. Defaults to `true`.

On iOS this requires your app to set `UNUserNotificationCenter.current().delegate`.
Without one, iOS reports the tap to nobody and no open can be captured.

Setting this to `false` does not prevent the iOS cold-start prewarm, which runs before
Dart does — opt that out with the `com.posthog.posthog.CAPTURE_PUSH_NOTIFICATION_OPENED`
key in `Info.plist`.

#### `<></>`

```dart
bool capturePushNotificationSubscriptions
```

Whether to automatically register this device's push token or Firebase
Installation ID (FID) with PostHog.

On iOS the native SDK swizzles the app delegate's remote-notification
registration callback; on Android it fetches the FCM token at startup when
`firebase-messaging` is on the classpath, or the FID when the app's manifest
enables `firebase_messaging_installation_id_enabled`. The host app must
still register with Firebase in FID mode. Either way the host app is still
responsible for requesting notification permission and calling
`registerForRemoteNotifications()` (iOS) — this only observes the result.

The startup fetch does not see later token refreshes; wire those to
Posthog.registerPushNotificationToken yourself.

**Flutter web, Windows and Linux:** not supported. Defaults to `true`.

#### `<></>`

```dart
PostHogCompression compression
```

Controls how request bodies are compressed before being sent to PostHog.

Set this to PostHogCompression.none when something between the app and
PostHog, e.g. a managed network or work profile, alters the gzip body.

**Flutter web:** not applied. The web SDK hooks onto an already-initialized
posthog-js instance, so set `disable_compression: true` in your
`posthog.init({...})` call instead to match PostHogCompression.none.

Defaults to PostHogCompression.gzip.

#### `<></>`

```dart
PostHogDataMode dataMode
```

Network connection types that can be used to send data on Apple platforms.

Defaults to PostHogDataMode.any.

#### `<></>`

```dart
bool debug
```

Whether the SDK emits verbose debug logs.

Defaults to `false`.

#### `<></>`

```dart
@experimental bool enableWindowsAndLinux
```

Whether the SDK is enabled on Windows and Linux.

Windows and Linux support is experimental. Defaults to `true`.
Set to `false` before Posthog.setup to disable the SDK on these
platforms. Other platforms are unaffected. Close the SDK before
changing this setting and calling setup again.

#### `<></>`

```dart
PostHogErrorTrackingConfig errorTrackingConfig
```

Configuration for error tracking and exception capture.

#### `<></>`

```dart
List<String>? evaluationContexts
```

Evaluation contexts sent with every `/flags` request, so only flags
tagged with at least one of these contexts are evaluated.

Defaults to `null`, which sends no contexts and evaluates every flag.
Flags without evaluation contexts are always evaluated. Use this to keep
flags meant for other apps or environments out of this app's requests.

**Flutter web:** not applied. posthog-js is initialized by your app, so
set `evaluation_contexts` in your `posthog.init({...})` call instead.

**Example:**

```dart
final config = PostHogConfig('<YOUR_PROJECT_TOKEN>')
  ..evaluationContexts = ['mobile-app', 'production'];
await Posthog().setup(config);
```

#### `<></>`

```dart
int flushAt
```

Number of queued events that triggers an automatic flush.

Defaults to `20`.

#### `<></>`

```dart
Duration flushInterval
```

Maximum time between automatic flush attempts.

Defaults to 30 seconds.

#### `PostHogConfig.host`

```dart
String get host
```

The PostHog ingestion host.

Defaults to `https://us.i.posthog.com`. The setter trims surrounding
whitespace and falls back to the default host when assigned a blank value.

#### `<></>`

```dart
PostHogLogsConfig logsConfig
```

Configuration for the logs subsystem (`Posthog().captureLog()` and the
`Posthog().logger` facade).

#### `<></>`

```dart
int maxBatchSize
```

Maximum number of events sent in a single batch.

Defaults to `50`.

#### `<></>`

```dart
int maxQueueSize
```

Maximum number of events stored in the local queue.

When the queue is full, the oldest events may be dropped by the native SDK.
Defaults to `1000`.

#### `<></>`

```dart
bool optOut
```

Whether the SDK starts with data collection disabled.

Defaults to `false`. Use `Posthog().optOut()` and `Posthog().optIn()` to
change this setting at runtime.

#### `<></>`

```dart
PostHogPersonProfiles personProfiles
```

Controls whether captured events create or update person profiles.

Defaults to PostHogPersonProfiles.identifiedOnly.

#### `<></>`

```dart
bool preloadFeatureFlags
```

Whether feature flags are loaded when the SDK starts.

Defaults to `true`, which means every SDK start issues a `/flags` request.
Set it to `false` if you evaluate flags lazily (via
`Posthog().reloadFeatureFlags()`) and want to avoid that request.

Note that `Posthog().identify()`, `Posthog().group()` and the
`set*PropertiesForFlags` helpers reload feature flags as well, so turning
preloading off only removes the request made at startup.

**Flutter web:** not applied. The web SDK hooks onto an already-initialized
posthog-js instance, so set
`advanced_disable_feature_flags_on_first_load`
in your `posthog.init({...})` call instead.

#### `<></>`

```dart
String projectToken
```

Your PostHog project token.

You can find it at:
https://us.posthog.com/settings/project-details#variables

#### `<></>`

```dart
PushIdentityProvider? pushIdentityProvider
```

Mints a signed identity-verification token for push subscription requests.

Only needed when your PostHog project requires identity verification for
push. The native SDK calls this with the current `distinctId` and `appId`
and attaches the returned token to the subscription request; return `null`
to send without one.

The token is minted by your backend (HS256, with `sub` = distinctId,
`app_id`, and `aud` = `posthog:push_identity`), never in the app.

The native SDKs cache the result per `(distinctId, appId)` and give this
callback 10 seconds before falling back to an unauthenticated request, so
a slow or throwing implementation degrades rather than blocking delivery.

Requires programmatic setup on both platforms. Under auto-init
(`com.posthog.posthog.AUTO_INIT`, Info.plist on iOS, AndroidManifest
`<meta-data>` on Android) the native SDK is already set up before Dart
runs and a later Posthog.setup is a no-op, so the provider is never
installed. Set `com.posthog.posthog.AUTO_INIT` to `false` and call
Posthog.setup.

**Flutter web, Windows and Linux:** not supported. Defaults to `null`.

#### `<></>`

```dart
PostHogRageClickConfig rageClickConfig
```

Configuration for rage-click autocapture on iOS and Mac Catalyst.

Rage-click autocapture is not currently supported on other platforms.

#### `<></>`

```dart
bool sendFeatureFlagEvent
```

Whether calls that evaluate feature flags capture `$feature_flag_called`.

Defaults to `true`.

#### `<></>`

```dart
bool sessionReplay
```

Whether mobile session replay is enabled for Android and iOS.

Requires Record user sessions to be enabled in PostHog project settings.
Defaults to `false`.

#### `<></>`

```dart
PostHogSessionReplayConfig sessionReplayConfig
```

Configuration for mobile session replay.

sessionReplay must be enabled for these options to take effect.

#### `<></>`

```dart
bool surveys
```

Enable Surveys

**Notes:**

- After calling `Posthog().close()`, surveys will not be rendered until the
  SDK is re-initialized and the next navigation event occurs.
- You must install `PosthogObserver` in your app for surveys to display.
  - See: https://posthog.com/docs/surveys/installation?tab=Flutter#step-two-install-posthogobserver
- For Flutter web, this setting will be ignored. Surveys on web use the
  JavaScript Web SDK instead.
  - See: https://posthog.com/docs/surveys/installation?tab=Web
- Surveys are not supported on Windows and Linux, where this setting is
  ignored.

Defaults to true.

### `PostHogDataMode`

```dart
enum PostHogDataMode
```

Controls which network connection types can be used for sending data.

This setting is currently applied only on Apple platforms.

##### Values

- `wifi`: Send data only on Wi-Fi connections.
- `any`: Send data on any available connection.

### `PostHogErrorTrackingConfig`

```dart
class PostHogErrorTrackingConfig
```

Configuration for PostHog error tracking and exception capture.

#### `PostHogErrorTrackingConfig()`

```dart
PostHogErrorTrackingConfig()
```

Creates an error tracking configuration with all autocapture disabled.

#### `<></>`

```dart
bool captureFlutterErrors
```

Enable automatic capture of Flutter framework errors.

Controls whether `FlutterError.onError` errors are captured.

Default: false

#### `<></>`

```dart
bool captureIsolateErrors
```

Enable automatic capture of isolate errors.

Only captures errors from the isolate where `Posthog().setup()` runs,
normally the main isolate. Errors from spawned background isolates are
not captured automatically. To capture them, call
`isolate.addPostHogErrorListener()` from the main isolate before resuming
an isolate spawned paused.

**Note:**

- Flutter web: Not supported

Default: false

#### `<></>`

```dart
bool captureNativeCrashes
```

Enable automatic capture of native C/C++ (NDK) crashes on Android.

Requires Android 12 (API 31) or later. A native crash kills the process
immediately, so the crash is captured on the next app launch from the
records the OS kept, as an `$exception` event with raw native stack
frames. Exception autocapture must also be enabled in the project's
error tracking settings.

For symbolicated stack traces, upload the app's `.so` debug symbols with
the PostHog Gradle plugin.
See: https://posthog.com/docs/error-tracking/upload-mappings/android

Because the event is sent from the next launch, properties like
`$app_version` reflect the app at capture time, not at crash time.

**Note:**

- Apple platforms: Not applicable (native crash capture is part of
  captureNativeExceptions)
- Flutter web: Not supported
- Windows and Linux: Not supported

Default: false

#### `<></>`

```dart
bool captureNativeExceptions
```

Enable automatic capture of exceptions in the native SDKs
(Android and Apple platforms).

Controls whether native exceptions are captured.

**Apple (iOS, macOS, tvOS):**

Native error tracking on Apple platforms is currently experimental

Captures Mach exceptions (e.g., EXC\_BAD\_ACCESS), POSIX signals
(e.g., SIGSEGV, SIGABRT), and uncaught NSExceptions.
Crashes are persisted to disk and sent as `$exception` events with
level "fatal" on the next app launch.
Not available on watchOS or visionOS due to platform limitations.

For symbolicated stack traces, add a build phase script to your
Xcode project to upload debug symbols.
See: https://posthog.com/docs/error-tracking/upload-source-maps/ios

**Android:**

Captures Java/Kotlin exceptions. For native C/C++ (NDK) crashes, also
enable captureNativeCrashes.

Stacktrace demangling for minified builds is supported by installing
the PostHog Gradle plugin to upload ProGuard/R8 mappings.
See: https://posthog.com/docs/error-tracking/upload-mappings/android

**Windows and Linux:** not supported.

Default: false

#### `<></>`

```dart
bool capturePlatformDispatcherErrors
```

Enable automatic capture of Dart runtime errors.

Controls whether `PlatformDispatcher.onError` errors are captured.

**Note:**

- Flutter web: Not supported

Default: false

#### `<></>`

```dart
bool captureSilentFlutterErrors
```

Enable capturing of silent Flutter errors.

Controls whether Flutter errors marked as silent
(`FlutterErrorDetails.silent = true`) are captured.

Default: false

#### `<></>`

```dart
PostHogExceptionStepsConfig exceptionSteps
```

Configuration for exception steps (breadcrumb-style context records
attached to every captured `$exception` as `$exception_steps`).

Record steps with `Posthog().addExceptionStep()`.

#### `<></>`

```dart
bool inAppByDefault
```

Configures whether stack trace frames are considered in-app by default
when the origin cannot be determined or no explicit includes/excludes
match.

- If true: Frames are inApp unless explicitly excluded (allowlist approach)
- If false: Frames are external unless explicitly included (denylist approach)

Default behavior when true:

- Local files (no package prefix) are inApp
- dart and flutter packages are excluded
- All other packages are inApp unless in inAppExcludes

**Note:**

- Flutter web: Not supported
- Android: Not supported

#### `<></>`

```dart
List<String> inAppExcludes
```

List of package names to exclude from in-app frames for exception tracking.

Use bare Dart package names without the `package:` URI prefix.

Example:

```dart
config.errorTrackingConfig.inAppExcludes.addAll([
  'third_party_lib',
  'analytics_package',
]);
```

All exception stack trace frames from these packages will be considered
external.

Note: inAppIncludes takes precedence over this setting.
Common packages to exclude:

- Third-party analytics packages
- External utility libraries
- Packages you don't control

**Note:**

- Flutter web: Not supported
- Android: Not supported

#### `<></>`

```dart
List<String> inAppIncludes
```

List of package names to be considered in-app frames for exception tracking.

Use bare Dart package names without the `package:` URI prefix.

Example:

```dart
config.errorTrackingConfig.inAppIncludes.addAll([
  'your_app',
  'your_company_utils',
]);
```

All exception stack trace frames from these packages will be considered
in-app.

This option takes precedence over inAppExcludes.
For Flutter/Dart, this typically includes:

- Your app's main package (e.g., "your\_app")
- Any internal packages you own (e.g., "your\_company\_utils")

**Note:**

- Flutter web: Not supported

### `PostHogEvent`

```dart
class PostHogEvent
```

Represents an event that can be modified or dropped before it is sent.

This class is used in before-send callbacks to allow modification of events
before they are sent to PostHog.

On iOS, macOS, Android, Windows and Linux the callbacks get the event the
SDK is about to send, with its system and registered properties already
added. It also carries its uuid, distinctId and timestamp.

```dart
config.beforeSend = [
  (event) {
    event.properties?.remove(r'$device_name');
    return event;
  },
];
```

#### `PostHogEvent()`

```dart
PostHogEvent({required String event, Map<String, Object>? properties, Map<String, Object>? userProperties, Map<String, Object>? userPropertiesSetOnce, Map<String, Object?>? options, String? uuid, String? distinctId, DateTime? timestamp})
```

Creates an event passed to a before-send callback.

The `event` is the event name to capture.

The optional `properties` are event properties that can be amended before
capture.

The optional `userProperties` are person properties to set with `$set`.

The optional `userPropertiesSetOnce` are person properties to set with
`$set_once`.

The optional `options` are the event's per-event options.

The optional `uuid`, `distinctId` and `timestamp` are set by the SDK on
every platform but web.

#### `<></>`

```dart
String? distinctId
```

The id of the person the event is captured for.

Set on iOS, macOS, Android, Windows and Linux, where a callback can
change it. `null` on web.

#### `<></>`

```dart
String event
```

The name of the event (e.g., 'button\_clicked', '$screen', '$exception')

#### `<></>`

```dart
Map<String, Object?>? options
```

Settings that tell PostHog how to process this event, sent apart from
its properties. See `Posthog.capture` for the known keys.

A callback can read, add, change or remove them. A null value means
unset.

#### `<></>`

```dart
Map<String, Object>? properties
```

The event's properties.

On iOS, macOS, Android, Windows and Linux, the map already holds the
system properties (like `$device_type` and `$session_id`), then the
registered properties, then the event's own, and the event is sent as
the callbacks leave it. `$set` and `$set_once` are in userProperties
and userPropertiesSetOnce instead.

On web, only the event's own properties are here; posthog-js adds the
rest later.

#### `<></>`

```dart
DateTime? timestamp
```

When the event happened.

Set on iOS, macOS, Android, Windows and Linux, where a callback can
change it. `null` on web.

#### `<></>`

```dart
Map<String, Object>? userProperties
```

User properties to set on the user profile ($set).

These properties will be merged with any existing user properties.

#### `<></>`

```dart
Map<String, Object>? userPropertiesSetOnce
```

User properties to set only once on the user profile ($set\_once).

These properties will only be set if they don't already exist on the user profile.

#### `<></>`

```dart
String? uuid
```

The event's unique id, a lowercase UUID v7.

Set on iOS, macOS, Android, Windows and Linux, where the SDK builds the
event before the callbacks run. `null` on web. The id is kept even when
a callback returns another PostHogEvent.

### `PostHogExceptionStepsConfig`

```dart
class PostHogExceptionStepsConfig
```

Configuration for exception steps.

Exception steps are breadcrumb-style context records recorded over time via
`Posthog().addExceptionStep()`. The SDK keeps a rolling, byte-bounded buffer
of these steps and attaches a snapshot to every captured `$exception` event
as `$exception_steps`, giving the error tracking UI a timeline of recent
activity leading up to each error.

The buffer is owned by the embedded native SDK (iOS/Android), so steps also
survive native fatal crashes and attach to the crash `$exception` reported
on the next launch.

**Flutter web:** the buffer lives in posthog-js. Steps are forwarded to it,
but they only attach to exceptions captured by posthog-js itself, not to
exceptions captured via `Posthog().captureException()` on web.

**Windows and Linux:** the buffer is kept in memory and attaches to every
`$exception` captured by the app. There are no native crash reports to
attach it to.

#### `PostHogExceptionStepsConfig()`

```dart
PostHogExceptionStepsConfig()
```

Creates an exception-steps configuration with native defaults.

#### `<></>`

```dart
bool enabled
```

Whether recording and attaching exception steps is enabled.

When disabled, `Posthog().addExceptionStep()` is a no-op and nothing is
attached. Defaults to `true`.

#### `<></>`

```dart
int maxBytes
```

Total UTF-8 byte budget for the rolling step buffer.

When adding a step would exceed the budget, the oldest steps are evicted
until the total fits. A single step larger than the budget is rejected
outright. Defaults to `32768` (32 KiB).

### `PostHogFeatureFlagResult`

```dart
class PostHogFeatureFlagResult
```

Represents the result of a feature flag evaluation.

Contains the flag key, whether it's enabled, the variant (for multivariate flags),
and any associated payload.

#### `PostHogFeatureFlagResult()`

```dart
const PostHogFeatureFlagResult({required String key, required bool enabled, String? variant, Object? payload})
```

Creates a feature flag evaluation result.

The `key` is the feature flag key that was evaluated.

The `enabled` value is the boolean result for boolean flags. For
multivariate flags, it is `true` when the flag evaluates to a variant and
`false` when it does not match.

The optional `variant` is the variant key for multivariate flags.

The optional `payload` is the JSON payload configured for the matched flag
or variant.

#### `<></>`

```dart
bool enabled
```

Whether the flag is enabled.

For boolean flags, this is the flag value.
For multivariate flags, this is true when the flag evaluates to any variant.

#### `<></>`

```dart
String key
```

The feature flag key.

#### `<></>`

```dart
Object? payload
```

The JSON payload associated with the flag, if any.

#### `<></>`

```dart
String? variant
```

The variant key for multivariate flags, or null for boolean flags.

### `PostHogFeatureFlagsLoaded`

```dart
class PostHogFeatureFlagsLoaded
```

The feature flags passed to Posthog.onFeatureFlags listeners and returned
by Posthog.reloadFeatureFlags.

Only enabled flags are included. When the latest load failed,
errorsLoading is `true` and the flags are the last known values, which
can be empty.

**Example:**

```dart
Posthog().onFeatureFlags((loaded) {
  if (loaded.errorsLoading) {
    // The values are the last known (cached) flags.
  }
  if (loaded.variants['new-checkout'] == 'test') {
    // Show the test variant.
  }
});
```

#### `PostHogFeatureFlagsLoaded()`

```dart
PostHogFeatureFlagsLoaded({required Map<String, Object?> variants, required bool errorsLoading})
```

Creates the loaded feature flags from `variants`, keeping only enabled
flags: `true`, or a non-empty variant string.

#### `<></>`

```dart
bool errorsLoading
```

Whether the latest attempt to load feature flags failed.

When it did, flags and variants hold the last known values.

**Flutter web:** the first load after Posthog.setup can be the current
flags with `false`, even if posthog-js's last load before that failed.

#### `PostHogFeatureFlagsLoaded.flags`

```dart
List<String> get flags
```

The keys of the enabled feature flags.

#### `<></>`

```dart
Map<String, Object> variants
```

The values of the enabled feature flags, keyed by flag key.

A value is `true` for an enabled boolean flag, or the variant String
for a multivariate flag. Disabled flags are not included.

### `PostHogFeatureFlagsSubscription`

```dart
class PostHogFeatureFlagsSubscription
```

A listener added with Posthog.onFeatureFlags.

Call unsubscribe to stop receiving feature flags updates.

#### `PostHogFeatureFlagsSubscription.unsubscribe`

```dart
void unsubscribe()
```

Stops the listener from receiving further updates. Calling it again has
no effect.

### `PostHogLogRecord`

```dart
class PostHogLogRecord
```

Represents a log record that can be modified or dropped before it is sent.

This class is passed to the before-send callbacks registered via
PostHogLogsConfig.beforeSend to allow modification of log records before
they are forwarded to the native SDK.

#### `PostHogLogRecord()`

```dart
PostHogLogRecord({required String body, PostHogLogSeverity level = PostHogLogSeverity.info, Map<String, Object>? attributes})
```

Creates a log record passed to a before-send callback.

The `body` is the log message.

The `level` is the severity, defaulting to PostHogLogSeverity.info.

The optional `attributes` are per-record attributes that can be amended
before capture.

#### `<></>`

```dart
Map<String, Object>? attributes
```

User-provided attributes for this record.

Note: Auto-captured context (distinct id, session id, screen name, app
state, active feature flags) is added by the native SDK at a later stage
and is not available in this map.

#### `<></>`

```dart
String body
```

The log message body.

#### `<></>`

```dart
PostHogLogSeverity level
```

The severity level of the record.

### `PostHogLogSeverity`

```dart
enum PostHogLogSeverity
```

Severity level for a structured log record captured via
`Posthog().captureLog()` or the `Posthog().logger` facade.

The levels map to OpenTelemetry severity numbers (`trace`=1, `debug`=5,
`info`=9, `warn`=13, `error`=17, `fatal`=21). The mapping is performed by
the native SDKs; the Flutter layer forwards the level by name (lowercase),
which both the Android and Apple SDKs parse case-insensitively.

##### Values

- `trace`: Finest-grained diagnostic detail. High-volume; usually only enabled while
  diagnosing a problem.
- `debug`: Diagnostic detail useful during development.
- `info`: Default level for regular runtime events.
- `warn`: Something unexpected that is not yet an error.
- `error`: A failure that should be looked at.
- `fatal`: A critical failure.

### `PostHogLogsConfig`

```dart
class PostHogLogsConfig
```

Configuration for the logs subsystem.

Assign values before calling `Posthog().setup(config)`. The identity and
tuning fields are forwarded to the native iOS/Android logs configuration;
beforeSend runs in Dart before a record is forwarded to the native SDK.

Every field that is `null` (or, for resourceAttributes, empty) is left at
the native SDK's default — it is not sent over the channel.

**Flutter web:** this configuration is **not** applied on web. The web SDK
hooks onto an already-initialized posthog-js instance, so configure logs in
your `posthog.init({...})` call instead. Only beforeSend runs on web (in
Dart).

**Windows and Linux:** logs are not supported. Only beforeSend runs (in
Dart); the records it keeps are then dropped.

#### `PostHogLogsConfig()`

```dart
PostHogLogsConfig()
```

Creates a logs configuration with native defaults.

#### `<></>`

```dart
List<BeforeSendLogCallback> beforeSend
```

Callbacks to intercept and modify log records before they are forwarded to
the native SDK.

Callbacks are invoked in order for records captured via
`Posthog().captureLog()` and the `Posthog().logger` facade. Each callback
receives the record (possibly modified by previous callbacks). Return a
possibly modified record to continue, or return `null` to drop it.
Blanking the body also drops the record.

**Example:**

```dart
config.logsConfig.beforeSend = [
  (record) {
    record.attributes?.remove('password');
    return record;
  },
  (record) => record.body.contains('secret') ? null : record,
];
```

**Note:**

- Runs in Dart on all platforms — it is intentionally not forwarded to the
  native SDKs' own `beforeSend`. Dart callbacks cannot cross the platform
  channel, and running it here gives identical behavior everywhere
  (including web). This mirrors the event PostHogConfig.beforeSend.
- Callbacks are synchronous.
- A callback that throws is logged, and the record is dropped.
- The W3C trace fields (`traceId`, `spanId`, `traceFlags`) are **not**
  part of PostHogLogRecord and are not visible here. They pass straight
  through to the native SDK, so they cannot be redacted or used to drop a
  record. Keep anything sensitive out of those fields; put it in `body` or
  PostHogLogRecord.attributes, which a callback can scrub or drop.

#### `<></>`

```dart
String? environment
```

Sets the OTLP `deployment.environment` resource attribute (e.g.
`production`, `staging`). When `null`, the native SDK's default is used
(no environment).

#### `<></>`

```dart
int? flushAt
```

Queue depth that triggers an immediate flush. When `null`, the native
default is used (20 on iOS/Android).

#### `<></>`

```dart
Duration? flushInterval
```

Periodic auto-flush interval. When `null`, the native default is used
(30s on iOS/Android).

#### `<></>`

```dart
int? maxBatchSize
```

Maximum number of records sent per POST. When `null`, the native default
is used (50 on iOS/Android).

#### `<></>`

```dart
int? maxBufferSize
```

Maximum number of buffered records before the oldest are dropped (FIFO).
When `null`, the native default is used (1000 on iOS/Android).

#### `<></>`

```dart
int? rateCapMaxLogs
```

Maximum number of logs accepted per rate-cap window before excess logs are
dropped. When `null`, the native default is used (500 on iOS/Android). A
non-positive value disables the cap natively.

#### `<></>`

```dart
Duration? rateCapWindow
```

Length of the rate-cap window. When `null`, the native default is used
(10s on iOS/Android).

#### `<></>`

```dart
Map<String, Object> resourceAttributes
```

Extra OTLP resource attributes merged into every payload.

SDK-managed identity keys (`service.*`, `telemetry.sdk.*`) take precedence
and cannot be overridden.

#### `<></>`

```dart
String? serviceName
```

Sets the OTLP `service.name` resource attribute.

When `null`, the native SDK's default is used (the app bundle id on Apple
platforms, the app namespace on Android).

#### `<></>`

```dart
String? serviceVersion
```

Sets the OTLP `service.version` resource attribute.

When `null`, the native SDK's default is used (the app version where the
platform provides one).

### `PostHogPersonProfiles`

```dart
enum PostHogPersonProfiles
```

Controls whether events create or update PostHog person profiles.

##### Values

- `never`: Never create person profiles from captured events.
- `always`: Create or update person profiles for all captured events.
- `identifiedOnly`: Create or update person profiles only after the user has been identified.

### `PostHogPlatformViewPrivacy`

```dart
enum PostHogPlatformViewPrivacy
```

Controls how a platform view is handled in session replay.

##### Values

- `mask`: Mask the view with a black rectangle (default).
- `capture`: Reveal the view content in session replay.

### `PostHogRageClickConfig`

```dart
class PostHogRageClickConfig
```

Configuration for rage-click autocapture on iOS and Mac Catalyst.

Assign an instance to PostHogConfig.rageClickConfig before calling
`Posthog().setup(config)`. Other platforms ignore this configuration.

#### `PostHogRageClickConfig()`

```dart
PostHogRageClickConfig()
```

Creates a rage-click configuration using the native defaults.

#### `<></>`

```dart
bool enabled
```

Whether rapid repeated taps are captured as `$rageclick` events.

Defaults to `true`.

#### `<></>`

```dart
int minimumTapCount
```

Number of consecutive taps required to capture a rage click.

Defaults to `3`.

#### `<></>`

```dart
double thresholdPoints
```

Maximum Manhattan distance, in logical points, between consecutive taps.

Defaults to `30`.

#### `<></>`

```dart
Duration timeoutInterval
```

Maximum time between consecutive taps in the same sequence.

Defaults to one second.

### `PostHogRouteFilter`

```dart
PostHogRouteFilter = bool Function(Route? route)
```

Filters routes before PosthogObserver captures screen views.

Return `true` to allow tracking for `route` and `false` to ignore it. By
default, only PageRoutes are tracked.

### `PostHogScreenshotColorMode`

```dart
enum PostHogScreenshotColorMode
```

Pixel format for Android native-screen captures in session replay.

##### Values

- `argb8888`: Preserve alpha and eight-bit color channels before compression.
- `rgb565`: Use half the bitmap memory with reduced color precision and no alpha.

### `PostHogSessionReplayConfig`

```dart
class PostHogSessionReplayConfig
```

Configuration for mobile session replay capture and masking.

Assign an instance to PostHogConfig.sessionReplayConfig before calling
`Posthog().setup(config)`.

#### `PostHogSessionReplayConfig()`

```dart
PostHogSessionReplayConfig()
```

Creates a session replay configuration with default masking enabled.

#### `PostHogSessionReplayConfig.captureNativeScreens`

```dart
bool get captureNativeScreens
```

Capture native screens that cover the Flutter UI (full-screen paywalls,
presented view controllers, native activities) via the native replay
SDK, so they appear in replay instead of a frozen Flutter frame.
When enabled and a detected screen cannot be captured, a single black
placeholder frame is sent instead; if that also fails, replay keeps
showing the last Flutter frame. With this flag off there is no
placeholder — nothing about replay changes.

Only full-screen, same-process screens are detected. Not captured:
partial-height sheets (e.g. Apple Pay, share sheet), other-process
content, Android dialogs/Custom Tabs, and iOS covers without an opaque
background — replay keeps showing the covered Flutter UI for those.

Opt-in: enabling this starts a lightweight occlusion detector. When false
(the default), the covered Flutter tree keeps recording, as before.

Captured native frames honor your maskAllTexts / maskAllImages
settings — with the defaults (both true) all native text and images are
masked; setting either false reveals it on native screens too.

Applies only to native screens presented over the whole app. For native
views embedded in the Flutter layout, see maskAllPlatformViews.

Can be changed at runtime after setup — turning it off before presenting
a sensitive native screen guarantees that screen is not captured.

Default: false. Requires native SDK support for on-demand capture.

#### `<></>`

```dart
bool captureTouches
```

Capture touch coordinates in session replay on Android and iOS.

Masking screenshots does not hide touches on a known keypad layout.
Set this before Posthog.setup. Runtime changes are not supported.
Disabling touches does not stop screenshot capture.

Default: true. Not supported on web or desktop.

#### `<></>`

```dart
bool maskAllImages
```

Enable masking of all images.
Default: true. `PostHogUnmaskWidget` can reveal known-safe Flutter images;
it overrides explicit masks within the same subtree too. Flutter web
requires canvas masking to be enabled as described in maskAllTexts.

Does not mask images drawn by CustomPainter. Enable maskCustomPaint or
wrap sensitive custom-painted widgets in PostHogMaskWidget to mask them.

#### `<></>`

```dart
bool maskAllPlatformViews
```

Mask all platform views (WebView, Maps, etc.) in session replay.

Default: true.

When true, every platform view is covered with a black rectangle in
session replay screenshots. Set to false to opt out globally, or wrap
individual views with PostHogPlatformView for per-view control.

Setting this false reveals every texture-backed view, including camera
previews (e.g. the `camera` plugin) — prefer per-view
PostHogPlatformView opt-ins over the global opt-out.

**iOS note:** among `UiKitView`s, setting this false only reveals
`WKWebView`-backed ones; maps, ARKit and other native views stay masked.
See PostHogPlatformViewPrivacy.capture.

Applies only to native views embedded in the Flutter layout. For native
screens presented over the whole app, see captureNativeScreens.

#### `<></>`

```dart
bool maskAllTexts
```

Enable masking of all text and text input fields.
Default: true. Wrap known-safe Flutter content in `PostHogUnmaskWidget`
to reveal it without disabling masking globally.

Sensitive Flutter inputs stay masked regardless of this flag, explicit
masks, or unmask widgets. This includes `obscureText`, password, email,
phone, name, address and URL keyboard types, and standard Flutter autofill
hints for identity, contact, address, authentication, and payment data.
Inputs without these signals are not automatically classified as
sensitive. Annotate them appropriately or keep global masking enabled.
`PostHogUnmaskWidget` overrides global and explicit masks for other content.

Flutter web requires canvas masking to be enabled by mounting a
`PostHogMaskWidget` or `PostHogUnmaskWidget` inside `PostHogWidget`, or by
declaring `session_recording.canvasCapture.maskRegionsFn` in `posthog.init`.
Declare it as `() => null` to skip frames before Flutter installs its mask
provider. Canvas recording must be enabled separately.

Does not mask text drawn by CustomPainter. Enable maskCustomPaint or
wrap sensitive custom-painted widgets in PostHogMaskWidget to mask them.

With captureNativeScreens enabled, setting this false also unmasks text
on captured native screens, including native input fields (passwords,
card numbers) you may not have built.

#### `<></>`

```dart
bool maskCustomPaint
```

Mask the full bounds of CustomPaint widgets with a painter or
foregroundPainter, including their children.
Default: false.

This is independent of maskAllTexts and maskAllImages. Canvas contents
cannot be inspected for individual text or images, so enabling this also
masks custom-painted decorations in Flutter widgets, including TabBar,
checkboxes, switches, and progress indicators. Framework scrollbar-only
painters are excluded, but their children are still checked for masks.
Disable MaterialApp's debugShowCheckedModeBanner when using this option:
its full-window CustomPaint otherwise masks the entire screen.

Frames containing a painter whose bounds cannot be determined, such as a
zero-sized CustomPaint, are skipped rather than sent with a missing mask.

#### `<></>`

```dart
double? sampleRate
```

Session replay sample rate between 0 and 1.
Local config has precedence over remote config when both are set.
If null, sampling is controlled by remote config (when available).

#### `<></>`

```dart
@experimental PostHogScreenshotColorMode screenshotColorMode
```

Pixel format for Android native-screen captures.

Applies only to screens recorded with captureNativeScreens.
Defaults to PostHogScreenshotColorMode.argb8888.
Set before `Posthog().setup(config)`.

#### `PostHogSessionReplayConfig.screenshotCompressionQuality`

```dart
@experimental int get screenshotCompressionQuality
```

Compression quality for Android replay screenshots.

Flutter screenshots use JPEG; native screens recorded with
captureNativeScreens use WebP. Defaults to `30`, clamped to `0`–`100`.
Higher values generally retain more detail and produce larger payloads.
Native capture on Android 10 uses lossless WebP at quality `100`; other
supported versions use lossy WebP. Does not change resolution.
Set before `Posthog().setup(config)`.

#### `PostHogSessionReplayConfig.screenshotScale`

```dart
@experimental double? get screenshotScale
```

Multiplier for the width and height of Android replay screenshots.

Defaults to `null`: Flutter screenshots capture at one pixel per logical
pixel and native screens recorded with captureNativeScreens use the
Android SDK default of one pixel per dp. An explicit value multiplies the
logical size of Flutter screenshots and the physical size of native
screens, so `1.0` captures native screens at physical resolution. Values
are clamped to `0.1`–`1.0`; NaN and infinity reset to `null`. Scaled
dimensions round up to at least one pixel without changing the logical
replay viewport. Masks round outward to cover output pixels; frames with
mask bounds that cannot be mapped safely are skipped.
Set before `Posthog().setup(config)`.

#### `<></>`

```dart
PostHogTextMaskPolicy? textMaskPolicy
```

Decides, per text node, what to mask — instead of all-or-nothing.

When set, every plain `Text`, `RichText`, and non-sensitive text input is
masked according to the PostHogTextMask the policy returns for its
rendered string, and maskAllTexts no longer applies to those nodes.
Ranges are masked at glyph precision, so a policy can hide an amount
while the label next to it stays readable:

```dart
// Mask numbers only: "Balance ₦2,450,000.00" keeps "Balance" visible.
config.sessionReplayConfig.textMaskPolicy =
    PostHogTextMaskPolicies.digits();

// Mask everything except a known-safe pattern.
config.sessionReplayConfig.textMaskPolicy =
    PostHogTextMaskPolicies.reveal(RegExp(r'^(Continue|Cancel)$'));

// Or decide per node, using its text, its widget, or both — here, two
// nodes with the same string are told apart by style.
config.sessionReplayConfig.textMaskPolicy = (text, widget) =>
    widget is RichText && widget.text.style?.fontWeight == FontWeight.bold
        ? const PostHogTextMask.none()
        : const PostHogTextMask.all();
```

`widget` is whichever widget actually produced the render object being
captured — `RichText` for `Text` and `RichText` alike, `EditableText`
for text inputs. It is not the outer `Text`/`TextField` an app writes:
`Text` is a thin wrapper over `RichText`, and there is no reliable way
to recover it across Flutter's internal composition. Reach for its
style, its `InlineSpan`, or (for inputs) properties like `obscureText`
and `readOnly` — not its `key`, which will be the framework's, not the
app's.

Precedence, highest first: sensitive inputs (`obscureText`, password,
card, and other sensitive autofill hints) are always fully masked;
`PostHogMaskWidget` masks and `PostHogUnmaskWidget` reveals its subtree
without consulting the policy; then the policy decides; maskAllTexts
only applies to text nodes when no policy is set.

The policy runs on the UI thread for every captured text node; keep it
fast. It applies to the Flutter widget tree only — text on captured
native screens still follows maskAllTexts, and custom-painted text
still needs maskCustomPaint. Can be changed at runtime; the next
frame uses the new policy.

It fails closed. Where glyph-precise rects can't be trusted to cover
everything the decision asked to hide, the whole node is masked
instead:

- the policy throws, or its ranges throw while being read;
- a range falls outside the text, or cuts into a grapheme cluster —
  Flutter lays out no box for the severed half, so it would otherwise
  stay readable;
- the node's style paints `shadows`, which selection boxes don't
  bound, so a masked glyph could leave a readable copy of itself
  wherever its shadow lands;
- the node is a paragraph containing a `WidgetSpan` and the decision
  yields anything other than exactly one rect — including
  `PostHogTextMask.none()` and `PostHogTextMask.only([])`. A
  `PostHogUnmaskWidget` nested in that paragraph still reveals its
  own subtree.

Default: null.

#### `<></>`

```dart
Duration throttleDelay
```

Throttling delay used to reduce the number of snapshots captured and reduce
performance impact.

This is used for capturing the view as a screenshot. The lower the number,
the more snapshots will be captured but higher the performance impact.
Defaults to 1s.

#### `<></>`

```dart
bool verifyScreenshotMaskAlignment
```

Verify that masks remain aligned while capturing session replay screenshots.

Android only. This applies only to native-screen captures enabled by
captureNativeScreens. Normal Flutter widget screenshots are rendered and
masked by Flutter and are unaffected.

Enabling this can preserve screenshots during pixel-only redraws, including
continuously animated content, but performs additional view hierarchy walks
while a screenshot is captured.

Default: false.

### `PostHogTextMask`

```dart
class PostHogTextMask
```

What session replay masks inside one text node.

A PostHogTextMaskPolicy returns one of these for every plain `Text`,
`RichText`, and non-sensitive text input that a replay frame captures.
Ranges are character offsets into the node's rendered string, exactly as
it was passed to the policy. Build one with the named constructors, or
match on the four subtypes.

#### `PostHogTextMask.all`

```dart
const PostHogTextMask.all()
```

Mask the whole node.

#### `PostHogTextMask.except`

```dart
const PostHogTextMask.except(Iterable<TextRange> ranges)
```

Mask the whole node except `ranges`.

An empty `ranges` masks the whole node.

#### `PostHogTextMask.none`

```dart
const PostHogTextMask.none()
```

Leave the whole node visible.

#### `PostHogTextMask.only`

```dart
const PostHogTextMask.only(Iterable<TextRange> ranges)
```

Mask only `ranges`; the rest of the node stays visible.

An empty `ranges` masks nothing.

### `PostHogTextMaskAll`

```dart
class PostHogTextMaskAll
```

PostHogTextMask.all: the whole node is masked.

#### `PostHogTextMaskAll()`

```dart
const PostHogTextMaskAll()
```

Creates a decision that masks the whole node.

### `PostHogTextMaskExcept`

```dart
class PostHogTextMaskExcept
```

PostHogTextMask.except: everything but ranges is masked.

#### `PostHogTextMaskExcept()`

```dart
const PostHogTextMaskExcept(Iterable<TextRange> ranges)
```

Creates a decision that masks everything except `ranges`.

#### `<></>`

```dart
Iterable<TextRange> ranges
```

The character ranges to leave visible.

### `PostHogTextMaskNone`

```dart
class PostHogTextMaskNone
```

PostHogTextMask.none: the whole node stays visible.

#### `PostHogTextMaskNone()`

```dart
const PostHogTextMaskNone()
```

Creates a decision that leaves the whole node visible.

### `PostHogTextMaskOnly`

```dart
class PostHogTextMaskOnly
```

PostHogTextMask.only: only ranges are masked.

#### `PostHogTextMaskOnly()`

```dart
const PostHogTextMaskOnly(Iterable<TextRange> ranges)
```

Creates a decision that masks only `ranges`.

#### `<></>`

```dart
Iterable<TextRange> ranges
```

The character ranges to mask.

### `PostHogTextMaskPolicies`

```dart
class PostHogTextMaskPolicies
```

Ready-made PostHogTextMaskPolicy implementations.

#### `PostHogTextMaskPolicies.digits`

```dart
PostHogTextMaskPolicy digits()
```

Masks every run of digits and leaves the surrounding words visible.

A run may contain grouping punctuation (`,` `.` `-`) and spaces between
its digits, so a formatted amount or card number is one mask:
`₦2,450,000.00` and `4111 1111 1111 1111` are each masked in full, and
in `Order 2 of 5` only the `2` and the `5` are.

#### `PostHogTextMaskPolicies.redact`

```dart
PostHogTextMaskPolicy redact(RegExp pattern)
```

Masks every match of `pattern` and leaves the rest of the node visible.

```dart
// Hide anything that looks like an email address.
PostHogTextMaskPolicies.redact(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'))
```

#### `PostHogTextMaskPolicies.reveal`

```dart
PostHogTextMaskPolicy reveal(RegExp pattern)
```

Masks the whole node except the matches of `pattern`.

```dart
// Keep currency codes readable inside otherwise masked amounts.
PostHogTextMaskPolicies.reveal(RegExp(r'\b(NGN|USD|GBP)\b'))
```

### `PostHogTextMaskPolicy`

```dart
PostHogTextMaskPolicy = PostHogTextMask Function(String text, Widget widget)
```

Decides what to mask in a text node, given its rendered string and the
widget that produced it.

Set one on `PostHogSessionReplayConfig.textMaskPolicy`. `widget` is the
`RichText` or `EditableText` that actually produced the render object —
not the outer `Text`/`TextField` an app writes, which Flutter composes
away — so inspect its style, its `InlineSpan`, or (for inputs)
properties like `obscureText` and `readOnly` to decide by more than the
string. It is called on the UI thread for every captured text node, so
keep it fast and free of side effects. Throwing masks the whole node.

### `PushIdentityProvider`

```dart
PushIdentityProvider = Future<String?> Function(String distinctId, String appId)
```

Mints a signed identity-verification token for a push subscription request.

Called by the native SDK with the current `distinctId` and `appId`. Return
`null` to send the request without an identity token.

### `ScreenNameExtractor`

```dart
ScreenNameExtractor = String? Function(RouteSettings settings)
```

Extracts a PostHog screen name from Flutter RouteSettings.

Return `null` to skip tracking the route. The `settings` argument is the
route settings from the route being pushed, popped to, or replaced.

### `defaultNameExtractor`

```dart
String? defaultNameExtractor(RouteSettings settings)
```

Returns RouteSettings.name as the screen name for `settings`.

Returns `null` when the route settings do not define a name.

### `defaultPostHogRouteFilter`

```dart
bool defaultPostHogRouteFilter(Route? route)
```

Returns whether `route` should be tracked by the default route filter.

The default implementation tracks only PageRoute instances.
