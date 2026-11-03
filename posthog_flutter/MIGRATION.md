# Migrating from posthog_flutter 5.x to 6.0

## Requirements

| | 5.x | 6.0 |
| --- | --- | --- |
| iOS deployment target | 13.0 | 15.0 |
| macOS deployment target | 10.15 | 11.0 |
| Android `minSdkVersion` declared by the plugin | 21 | 23 |
| iOS and macOS dependency manager | CocoaPods or Swift Package Manager | Swift Package Manager only |
| Flutter for iOS and macOS builds | 3.27 | 3.41 |

The Dart minimum (`>=3.6.0`) is unchanged. Android, web, Windows and Linux builds aren't affected by the Swift Package Manager requirement.

### iOS and macOS

Raise your app's deployment targets. A lower target fails the build. Set **Minimum Deployments** for the `Runner` target in Xcode (**Runner > General > Minimum Deployments**), which sets `IPHONEOS_DEPLOYMENT_TARGET` and `MACOSX_DEPLOYMENT_TARGET`.

If you keep a `Podfile` for other plugins, raise its platform too:

```ruby
# ios/Podfile
platform :ios, '15.0'

# macos/Podfile
platform :osx, '11.0'
```

### Move from CocoaPods to Swift Package Manager

posthog_flutter 6.0 has no podspec. On iOS and macOS, it installs only through Swift Package Manager.

**If you ignore this, the build stops.** With Swift Package Manager turned off, `flutter build` exits with `Plugin posthog_flutter is only compatible with Swift Package Manager`.

1. Use Flutter 3.41 or later. The plugin's `Package.swift` depends on the `FlutterFramework` package, which Flutter generates starting with 3.41.
2. Turn Swift Package Manager on if it's off. It's on by default from Flutter 3.44. On 3.41 to 3.43, or if you turned it off, run:

   ```sh
   flutter config --enable-swift-package-manager
   ```

3. Run your app. Flutter adds Swift Package Manager to the Xcode project on its own.

Other plugins that only support CocoaPods keep working: Flutter installs them through your `Podfile` and installs posthog_flutter as a Swift package. Keep the `Podfile` in that case.

If every plugin in your app supports Swift Package Manager, you can remove CocoaPods. This is optional. Follow [Flutter's steps](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers#how-to-remove-cocoapods-integration).

**Add-to-app:** Flutter doesn't support Swift Package Manager in Flutter modules yet ([flutter/flutter#146957](https://github.com/flutter/flutter/issues/146957)), and its build stops for a plugin without a podspec. If you embed Flutter as a module in an iOS or macOS app, stay on posthog_flutter 5.x until Flutter adds support.

### Android

`posthog-android` has required `minSdkVersion` 23 since 3.39.0, so an app on 21 or 22 already could not build with this plugin. The plugin now declares the same value, and you have nothing to change.

### Native SDKs and Xcode

| | 5.x | 6.0 |
| --- | --- | --- |
| `posthog-ios` | `>= 3.92.3, < 4.0.0` | `>= 4.0.0, < 5.0.0` |
| `posthog-android` | `[3.75.0, 4.0.0)` | `[4.0.0, 5.0.0)` |
| Xcode | Not set by the plugin | 26 or later |

Don't add these native SDKs to your app separately at a different major version.

## Breaking API changes

These all fail at compile time unless noted otherwise.

### `getFeatureFlagResult(sendEvent:)` is now `sendFeatureFlagEvent:`

The parameter is also now `bool?`. See [the default change](#getfeatureflagresult-follows-your-config) below.

```dart
// Before
await Posthog().getFeatureFlagResult('my-flag', sendEvent: false);

// After
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: false);
```

### `PostHogConfig.apiKey` is removed

Read `projectToken` instead. The constructor already takes the token as its first argument.

```dart
// Before
final token = config.apiKey;

// After
final token = config.projectToken;
```

### `com.posthog.posthog.API_KEY` is removed

Apps that start the SDK from `AndroidManifest.xml` or `Info.plist` must rename the key. **This does not fail at build time.** With only the old key, the SDK logs an error and does not start, so the app sends no data.

```xml
<!-- AndroidManifest.xml, before -->
<meta-data android:name="com.posthog.posthog.API_KEY" android:value="<YOUR_PROJECT_TOKEN>" />

<!-- AndroidManifest.xml, after -->
<meta-data android:name="com.posthog.posthog.PROJECT_TOKEN" android:value="<YOUR_PROJECT_TOKEN>" />
```

```xml
<!-- Info.plist, before -->
<key>com.posthog.posthog.API_KEY</key>
<string><YOUR_PROJECT_TOKEN></string>

<!-- Info.plist, after -->
<key>com.posthog.posthog.PROJECT_TOKEN</key>
<string><YOUR_PROJECT_TOKEN></string>
```

### `Posthog().enable()` and `disable()` are removed

```dart
// Before
await Posthog().disable();
await Posthog().enable();

// After
await Posthog().optOut();
await Posthog().optIn();
```

### `PostHogConfig.sendFeatureFlagEvents` is removed

```dart
// Before
config.sendFeatureFlagEvents = false;

// After
config.sendFeatureFlagEvent = false;
```

### `Posthog().getFeatureFlagPayload()` is removed

`getFeatureFlagPayload()` never captured `$feature_flag_called` on iOS, macOS, Android, Windows or Linux. Pass `sendFeatureFlagEvent: false` to keep it that way. Without it, the replacement call captures the event when your config allows it.

```dart
// Before
final payload = await Posthog().getFeatureFlagPayload('my-flag');

// After
final result = await Posthog().getFeatureFlagResult(
  'my-flag',
  sendFeatureFlagEvent: false,
);
final payload = result?.payload;
```

### `PostHogSessionReplayConfig.debouncerDelay` is removed

```dart
// Before
config.sessionReplayConfig.debouncerDelay = const Duration(seconds: 2);

// After
config.sessionReplayConfig.throttleDelay = const Duration(seconds: 2);
```

### `PostHogDataMode.cellular` is removed

It always behaved like `any`, so sending does not change.

```dart
// Before
config.dataMode = PostHogDataMode.cellular;

// After
config.dataMode = PostHogDataMode.any;
```

### `toMap()` and `PostHogFeatureFlagResult.fromMap()` are removed

They serialized the internal platform-channel format and have no replacement. `toMap()` is gone from `PostHogConfig`, `PostHogBootstrapConfig`, `PostHogLogsConfig`, `PostHogRageClickConfig`, `PostHogSessionReplayConfig`, `PostHogErrorTrackingConfig` and `PostHogExceptionStepsConfig`. To build a result, for example in a test, call the `PostHogFeatureFlagResult` constructor, which stays public.

### `beforeSend` callbacks are synchronous

`BeforeSendCallback` is now `PostHogEvent? Function(PostHogEvent)`, and `BeforeSendLogCallback` is `PostHogLogRecord? Function(PostHogLogRecord)`. An `async` callback is a compile error. Load what it needs ahead of time and read it synchronously.

```dart
// Before
config.beforeSend = [
  (event) async {
    final allowed = await loadAllowList();
    return allowed.contains(event.event) ? event : null;
  },
];

// After
final allowed = await loadAllowList();
config.beforeSend = [
  (event) => allowed.contains(event.event) ? event : null,
];
```

### Platform interface changes

These affect only code that calls, extends or fakes `PosthogFlutterPlatformInterface`, `PosthogFlutterIO` or `PosthogFlutterWeb` directly, such as test mocks. `Posthog().optIn()` and `optOut()` are unaffected.

- `enable()` and `disable()` are now `optIn()` and `optOut()`.
- `getFeatureFlagPayload()` is removed.
- `getFeatureFlagResult({required String key, bool sendEvent = true})` is now `getFeatureFlagResult({required String key, bool? sendFeatureFlagEvent})`.
- `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException` take an `options` map.
- `captureAi()` is new. The base class throws `UnimplementedError` unless you override it.
- `isFeatureEnabled()` takes `defaultValue`.
- `reloadFeatureFlags()` returns a `Future<PostHogFeatureFlagsLoaded>`.

```dart
// Before
@override
Future<void> disable() async {}

// After
@override
Future<void> optOut() async {}
```

### `onFeatureFlags` and `reloadFeatureFlags()`

`PostHogConfig.onFeatureFlags` now receives a `PostHogFeatureFlagsLoaded`, and `reloadFeatureFlags()` returns a `Future<PostHogFeatureFlagsLoaded>`. It has `flags`, `variants` and `errorsLoading`.

```dart
// Before
config.onFeatureFlags = () {
  // ...
};

// After
config.onFeatureFlags = (loaded) {
  if (!loaded.errorsLoading) {
    // Use loaded.variants
  }
};
```

## Behavior changes

### Events go to capture v1

**This is a silent change if you use a reverse proxy or self-host.** On iOS, macOS, Android, Windows and Linux, events go to `/i/v1/analytics/events` instead of `/batch/`, and `captureAi` events go to `/i/v1/ai/events`. PostHog Cloud and the managed reverse proxy already serve the new paths. Most apps upgrade without code changes, and nothing here produces a compile error.

| Platform | Sent by | 6.0 |
| --- | --- | --- |
| iOS and macOS | posthog-ios 4.x | capture v1 |
| Android | posthog-android 4.x | capture v1 |
| Windows and Linux | posthog_flutter's own Dart client | capture v1 |
| Web | the posthog-js your app loads | unchanged |

Web doesn't move to capture v1 in this release. It keeps posthog-js and its current endpoints. On web, `options` are sent as the legacy option properties, and `captureAi` sends nothing.

For the changes every capture v1 SDK shares, such as event options, limits and per-event results, see [Upgrading to capture v1 SDKs](https://posthog.com/docs/libraries/capture-v1). On iOS, macOS and Android, capture v1 comes from the native SDKs, so the Capture v1 sections of the [iOS](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#capture-v1) and [Android](https://github.com/PostHog/posthog-android/blob/main/docs/migration-3.x-to-4.0.md#endpoints) guides apply there too. Windows and Linux are covered [below](#capture-v1-on-windows-and-linux).

<!-- TODO(capture-v1): the iOS `#capture-v1` and Android `#endpoints` / `#hosts-without-capture-v1` anchors exist only on the posthog-ios and posthog-android `feat/v4-capture-v1` branches, not on `main` yet. Check these links once both 4.0 guides merge. -->

#### Checklist

You need to change code if your app does any of these:

- sends events to a self-hosted PostHog or a reverse proxy that doesn't serve `/i/v1/analytics/events` and `/i/v1/ai/events`
- identifies users with a distinct ID over 200 UTF-8 bytes, such as a JWT
- captures events whose name is over 200 UTF-8 bytes
- sets `projectToken` to a personal API key (`phx_...`)
- sets `$lib` or `$lib_version` and expects PostHog to store that value
- reads `$session_id` or `$window_id` from the raw request body, for example in a proxy
- relies on a `Retry-After` longer than 30 seconds
- on Windows or Linux, registers or passes a property with the same key as one the SDK sets, such as `$os` or `$is_identified`, and expects the SDK's value to win
- on Windows or Linux, returns a `PostHogEvent` from `beforeSend` without the event's `options`
- on Windows or Linux, alerts on the SDK's debug log lines
- on Windows or Linux, calls `exit()` without awaiting the calls before it or `Posthog().close()`

#### Reverse proxies and self-hosting

Before you upgrade, make your own proxy:

- forward `/i/v1/analytics/events` and `/i/v1/ai/events`
- pass `Authorization` (the project token, sent as `Bearer <token>`), every `PostHog-*` header, `Content-Type`, `Content-Encoding` and `User-Agent` through unchanged. PostHog answers `401` without `Authorization` and `400` without the others, and the batch is dropped.
- if your proxy strips other credentials, keep `Authorization` values that start with `Bearer phc_`, `Bearer phs_` or `Bearer phx_`, plus the exact `Bearer <key>` of an older key without a prefix
- accept request bodies up to 20 MB. AI requests are often larger than 1 MB, the default limit in nginx and ingress-nginx.
- pass PostHog's response body through unchanged, because a 2xx whose body isn't PostHog's `{"results": {...}}` drops the events instead of retrying them

PostHog's managed reverse proxy already does this. See the [proxy guides](https://posthog.com/docs/advanced/proxy).

The SDK doesn't fall back to `/batch/`. On Windows and Linux, a 404 is retried, events stay queued until the route is served, and the SDK prints one warning, also without `debug`. Other statuses that aren't retried, such as 401, 403 or 405, drop the batch. See the [iOS](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#hosts-without-capture-v1) and [Android](https://github.com/PostHog/posthog-android/blob/main/docs/migration-3.x-to-4.0.md#hosts-without-capture-v1) guides for those platforms.

### Feature flag payloads

On iOS, macOS and Android, a malformed, empty or whitespace-only payload from `getFeatureFlagResult()` is now `null` instead of the raw string. On Android, a JSON `null` payload is also `null` instead of the string `"null"`.

On iOS and macOS, string values in `PostHogBootstrapConfig.featureFlagPayloads`, such as `"123"`, stay strings instead of being decoded to numbers or booleans.

### Lifecycle events on iOS and macOS

`Application Installed`, `Application Updated` and `Application Opened` no longer include `version` and `build`. Update insights, cohorts and filters that use them to `$app_version` and `$app_build`. Android still sends them.

### Network reachability on iOS and macOS

A path that needs user action, such as a VPN waiting for a password, counts as reachable, and queues pause while cellular data is off for the app. Events captured in the first 100 ms after setup may leave out `$network_wifi` and `$network_cellular`. Events still on disk from a `posthog-ios` 2.x SDK are deleted instead of sent.

### Personal API keys

A personal API key (`phx_...`) in `projectToken` now skips `setup()` with one log line, so the SDK doesn't start and the key is never sent. Use your project token (`phc_...`).

### Capture v1 on Windows and Linux

Windows and Linux send events through posthog_flutter's own Dart client, not a native SDK. This section covers what the native guides cover for the other platforms.

#### Event validation

Capture v1 checks each event on its own and drops only the invalid ones, so the rest of the batch is delivered.

- The SDK drops an event with an empty event name before sending it, as in 5.x. With `debug` on, it logs the drop.
- PostHog drops an event whose name is over 200 UTF-8 bytes. Legacy capture had no limit on event name length.
- PostHog drops an event whose distinct ID is over 200 UTF-8 bytes. Legacy capture shortened the ID to 200 characters and kept the event. If you identify users with a long ID, such as a JWT or a long email address, shorten or hash it before you upgrade. Otherwise every event for that user is dropped.
- `identify` with an empty or whitespace-only distinct ID is ignored, as in 5.x.
- A `NaN` or infinite `double` property value is removed and the event is still sent, as in 5.x. Inside a list, it's sent as `null`.
- The SDK drops an event whose name, distinct ID, `$session_id` or `$window_id` holds a lone UTF-16 surrogate, such as a string cut in the middle of an emoji, and sends the rest of the batch. With `debug` on, it logs the drop. A lone surrogate in a property or option becomes U+FFFD and the event is sent. `identify` with a distinct ID that holds one is ignored, so the ID isn't saved. In 5.x, legacy capture rejected the whole batch for a lone surrogate anywhere in it. <!-- TODO(capture-v1): lands with #703; remove this line if #703 doesn't merge before release. -->
- The SDK doesn't report these drops to your code. With `debug` on, it logs how many events PostHog dropped and why (see [Logs](#logs)).

#### SDK identity

PostHog sets `$lib` and `$lib_version` from the `PostHog-Sdk-Info` request header, `posthog-flutter/<version>`.
The SDK removes `$lib` and `$lib_version` from the properties it sends.
A value you set in properties, in a registered property or in `beforeSend` doesn't reach PostHog.

#### Property precedence

An event's properties are the SDK's, then registered properties, then the event's own, so your value now wins for that event. In 5.x, the SDK's values won.
`beforeSend` runs after that merge and sees the result.

A registered or passed `$session_id` that is a non-empty string replaces the SDK's session ID, which can detach events from their session.

#### Session and window IDs

Capture v1 sends `$session_id` and `$window_id` as top-level `session_id` and `window_id` fields, not as properties.
The SDK moves them out of `properties` for you.

- A string value, including an empty string, is sent unchanged.
- Any other value is removed and not sent. With `debug` on, the SDK logs a warning that names the key and the value's JSON type, never the value.
- A `null` value counts as unset and is removed without a warning.

In PostHog, the events still have `$session_id` and `$window_id`.

#### Event options

The legacy option properties, the `$`-prefixed properties legacy capture reads as settings, still work.
When the event is sent, the SDK removes each one from `properties` and uses it for its option:

| Legacy option property | Option |
| --- | --- |
| `$process_person_profile` | `process_person_profile` |
| `$cookieless_mode` | `cookieless_mode` |
| `$ignore_sent_at` | `disable_skew_correction` |
| `$product_tour_id` | `product_tour_id` |

- An option you pass or set in `beforeSend` wins over its legacy option property. A `null` option counts as unset, so the legacy option property fills it.
- Option values are sent as given. PostHog drops an event whose option value it can't read.
- Other option keys are sent unchanged.
- There are no global options. To set one for every event, register its legacy option property, for example `Posthog().register(r'$cookieless_mode', true)`.
- A registered legacy option property also reaches `$identify`, `$create_alias` and `$groupidentify`. If it turns person processing off, PostHog accepts those events and then drops them with an ingestion warning, and the SDK doesn't report it.
- Person processing is sent as the `process_person_profile: false` option only while it's off, instead of a `$process_person_profile` property on every event.
- Events still queued on disk by 5.x are sent to capture v1 after the update, with their legacy option properties moved to options.

**Review your `beforeSend` callbacks for the new event shape.** On Windows and Linux, `beforeSend` sees the options the SDK adds, including `process_person_profile: false`. A callback that returns a new `PostHogEvent` or replaces `event.options` without that key turns person processing on for that event. A legacy option property that a callback adds doesn't replace an option that is already set. `beforeSend` doesn't see `$identify`, `$create_alias`, `$groupidentify` or `$feature_flag_called`.

On iOS, macOS and Android, `beforeSend` sees only the options you passed. The native SDK adds its own options after the hook.

<!-- TODO(capture-v1): if #682 lands in 6.0, the Dart beforeSend on iOS, macOS and Android sees the event the native SDK built, including its options; update the line above. -->

<!-- TODO(capture-v1): on Windows and Linux, `$exception_steps` is added to `$exception` events after `beforeSend`, so a hook can't remove it (KNOWN-GAP against SD-25c, Eli's Option 1 moves it before the hook). Document it here or fix it before release. -->

#### Retries

- The SDK retries network errors and 404, 408, 429, 500, 502, 503 and 504 responses. Other statuses drop the batch, such as a 402 when you're over your billing limit. A product quota, such as for AI events, instead drops only those events inside a 2xx. 5.x retried 408, 429, every 5xx and 3xx responses, and didn't retry 404.
- When the response asks to retry only some events, the SDK keeps those events queued and removes the rest.
- After a failed send, the wait before the next one doubles from 1 second up to 30 seconds, with up to 25% random jitter. Retries have no limit: queued events stay until they're delivered or a full queue drops the oldest. In 5.x, a failed batch was retried up to 3 times, 3 seconds apart, within the same flush.
- A `Retry-After` header is a floor under that wait, capped at 30 seconds. In 5.x it had no cap.
<!-- TODO(capture-v1): the 1 s starting wait is the mobile divergence from the fleet's 100 ms that Eli hasn't confirmed yet (proposed 2026-11-02; desktop uses the same value). Keep or change this line once he decides. -->
- A 2xx response without PostHog's per-event results drops the batch. It isn't retried, because PostHog may have stored some of the events.
- A request times out after 10 seconds without progress, and an AI request after 60 seconds. In 5.x, a request timed out after 10 seconds in total.

#### Redirects

The SDK follows a 307 or 308 redirect only to the origin of `host` (same scheme, host and port), at most 5 times, and resends the same body and headers.
Any other redirect drops the batch.
In 5.x, no redirect was followed and the batch stayed queued.
If a proxy redirects capture requests to another host, point `host` at the final host.

#### Batches and size limits

- A request carries at most `maxBatchSize` events and 5 MiB. The SDK sends as soon as 5 MiB of events is queued, even before `flushAt` is reached. In 5.x, batches were limited by event count only.
- A larger event is sent alone.
- A `413` for a batch of more than one event halves `maxBatchSize` and `flushAt`, and the events are sent again in smaller batches. A `413` for a single event drops it.
- The SDK doesn't limit the size of an analytics event, as in 5.x.

#### AI events

- `captureAi` events have their own on-disk queue of up to `captureAiMaxQueueSize` events (100 by default) and 50 MiB, and the oldest are dropped first. `maxQueueSize` doesn't apply.
- An event over `captureAiMaxEventBytes` (8 MiB plus 64 KiB by default) is dropped, and `captureAi` returns `null`. You can only lower the limit.
- AI requests are gzipped unless you set `captureAiCompression` to `PostHogCompression.none`. `compression` doesn't apply.
- AI requests time out after 60 seconds without progress, or `captureAiTimeout`.
<!-- TODO(capture-v1): gzip by default, the 100-event and 50 MiB queue and the 60 s timeout follow the mobile AI-lane defaults Eli hasn't confirmed yet (DIVERGENCES "Accepted divergences", proposed 2026-11-02 for iOS and Android; desktop uses the same values). Update these lines if he changes any default. -->
- AI events use `flushAt` and `maxBatchSize`, like other events.
- `flush()` and `close()` also send AI events, and AI events left on disk are sent after the next `setup()`.
- PostHog drops an event sent with `captureAi` whose name doesn't start with `$ai_`. With `debug` on, the SDK logs a warning for it. `capture` never sends events to the AI endpoint.

#### Logs

All of these log only with `debug` on, except the 404 warning.

- One line per batch reports the events PostHog dropped, with their reasons, and the repeated-uuid copies it dropped, for example `Capture /i/v1/analytics/events dropped 1 of 20 events for good (event_name_too_long: 1) and 0 repeated-uuid copies.` 5.x had no such line.
- A failed flush logs `Error while flushing PostHog /i/v1/analytics/events` or `/i/v1/ai/events` and the error, without the response body. In 5.x the line was `Error while flushing PostHog` and the error included the response body. Update any log-based alerts that match the old text.
- The debug log no longer includes the properties of captured and sent events. To inspect events, use `beforeSend`.

#### Timestamps and IDs

- An event's timestamp is taken before `beforeSend` runs.
- Timestamps are UTC with 3 or 6 fractional digits, as in 5.x. The SDK doesn't check for future timestamps.
- Event uuids, request IDs and anonymous distinct IDs are UUID v7. You can't set an event's uuid, so events never repeat one.

#### Writes to disk

An event is no longer on disk when `capture`, `screen`, `captureException`, `captureFeatureView`, `captureFeatureInteraction`, `identify`, `alias`, `group` or `setPersonProperties` returns, only when the returned future completes. One you didn't await can be lost if the app crashes or calls `exit()` right after. Await the call, or `Posthog().close()`, before `exit()`. Only `close()` also covers events the SDK captures itself, such as `$feature_flag_called`. An `identify` not awaited before `exit()` can lose its `$identify` event for good, because the new ID is already saved. `close()` can now take up to 4 seconds, and a later `setup()` waits for the queue's file work.

### `getFeatureFlagResult()` follows your config

**This is a silent change with no compile error.** When you omit `sendFeatureFlagEvent`, `getFeatureFlagResult()` now uses `PostHogConfig.sendFeatureFlagEvent` instead of always capturing `$feature_flag_called`. This matches `getFeatureFlag()` and `isFeatureEnabled()`.

It only affects apps that set `config.sendFeatureFlagEvent = false`. Those apps stop sending `$feature_flag_called` from `getFeatureFlagResult()`, so insights and experiments that rely on that event can receive less data. To keep the event for a call:

```dart
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: true);
```

On web, `PostHogConfig.sendFeatureFlagEvent` is not applied to posthog-js, so an omitted value keeps the posthog-js default, which captures the event. Pass `sendFeatureFlagEvent: false` to suppress it on web.

## New features

- An `options` argument on `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException`, and `PostHogEvent.options` in `beforeSend`. `process_person_profile`, `cookieless_mode`, `disable_skew_correction` and `product_tour_id` win over their legacy option properties (`$process_person_profile`, `$cookieless_mode`, `$ignore_sent_at` and `$product_tour_id`). Other keys are sent unchanged. On web, known keys are sent as those legacy option properties and other keys are dropped. On web, `process_person_profile` has no effect, and the options of `identify`, `setPersonProperties`, `alias` and `group` are dropped.
- `captureAi` for `$ai_*` events. It returns the event's UUID, or `null` when the event isn't admitted. On web it sends nothing and returns `null`.
- `PostHogConfig.captureAiCompression`, `captureAiMaxQueueSize`, `captureAiTimeout` and `captureAiMaxEventBytes` for `captureAi` requests. They don't apply on web.

## Upgrade checklist

- [ ] Use Flutter 3.41 or later and make sure Swift Package Manager is on.
- [ ] Don't upgrade yet if you embed Flutter as an iOS or macOS add-to-app module.
- [ ] Raise iOS to 15.0 and macOS to 11.0 in your Xcode projects, and in any `Podfile` you keep.
- [ ] Rename `com.posthog.posthog.API_KEY` to `com.posthog.posthog.PROJECT_TOKEN` in `AndroidManifest.xml` and `Info.plist`.
- [ ] Use Xcode 26 or later.
- [ ] If you run your own reverse proxy or self-host, serve `/i/v1/analytics/events` and `/i/v1/ai/events` first.
- [ ] Shorten or hash distinct IDs over 200 UTF-8 bytes.
- [ ] Make `beforeSend` callbacks, including `PostHogLogsConfig.beforeSend`, synchronous.
- [ ] On Windows and Linux, review your `beforeSend` callbacks for the new event shape.
- [ ] Update `onFeatureFlags` callbacks to take a `PostHogFeatureFlagsLoaded`.
- [ ] Move anything that reads `version` or `build` on iOS and macOS lifecycle events to `$app_version` and `$app_build`.
- [ ] If you set `sendFeatureFlagEvent = false`, check whether anything relies on `$feature_flag_called` from `getFeatureFlagResult()`.
- [ ] Add `sendFeatureFlagEvent: false` wherever you replace `getFeatureFlagPayload()`.
- [ ] Fix the remaining compile errors using the sections above, including any test fakes of the platform classes.
