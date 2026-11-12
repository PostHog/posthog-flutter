# Migration guide

## 5.x → 6.0

### Requirements

| | 5.x | 6.0 |
| --- | --- | --- |
| iOS deployment target | 13.0 | 15.0 |
| macOS deployment target | 10.15 | 11.0 |
| Android `minSdkVersion` declared by the plugin | 21 | 23 |
| iOS and macOS dependency manager | CocoaPods or Swift Package Manager | Swift Package Manager only |
| Flutter SDK | 3.27 | 3.41 |

posthog_flutter 6.0 needs the Flutter SDK 3.41 or later on every platform: `flutter pub get` fails on an older Flutter, including in Android-only apps. The declared Dart minimum (`>=3.6.0`) is unchanged, but Flutter 3.41 ships a newer Dart, so that is the real minimum. Only iOS and macOS builds need Swift Package Manager.

#### iOS and macOS

Raise your app's deployment targets. A lower target fails the build. Set **Minimum Deployments** for the `Runner` target in Xcode (**Runner > General > Minimum Deployments**), which sets `IPHONEOS_DEPLOYMENT_TARGET` and `MACOSX_DEPLOYMENT_TARGET`.

If you keep a `Podfile` for other plugins, raise its platform too:

```ruby
# ios/Podfile
platform :ios, '15.0'

# macos/Podfile
platform :osx, '11.0'
```

#### Move from CocoaPods to Swift Package Manager

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

**Add-to-app:** `flutter build swift-package` still installs a Flutter module's plugins with CocoaPods on current stable releases, so it stops with `Unable to find a specification for 'posthog_flutter' depended upon by 'FlutterPluginRegistrant'` because posthog_flutter has no podspec. Flutter fixed this in [flutter/flutter#184590](https://github.com/flutter/flutter/issues/184590), which isn't in a stable release yet. If you embed Flutter as a module in an iOS or macOS app, stay on posthog_flutter 5.x until it is. On Flutter 3.44 or later, you can instead embed Flutter in an iOS or macOS app from a Flutter app project (`flutter create`, not `-t module`) by following Flutter's Swift Package Manager add-to-app steps for [iOS](https://docs.flutter.dev/add-to-app/ios/project-setup) or [macOS](https://docs.flutter.dev/add-to-app/macos/project-setup); this works with posthog_flutter 6.

#### Android

`posthog-android` has required `minSdkVersion` 23 since 3.39.0, so an app on 21 or 22 already could not build with this plugin. The plugin now declares the same value, and you have nothing to change.

#### Native SDKs and Xcode

| | 5.x | 6.0 |
| --- | --- | --- |
| `posthog-ios` | `>= 3.92.3, < 4.0.0` | `>= 4.0.0, < 5.0.0` |
| `posthog-android` | `[3.75.0, 4.0.0)` | `[4.0.0, 5.0.0)` |
| Xcode | Not set by the plugin | 26 or later |

Don't add these native SDKs to your app separately at a different major version.

On Android, posthog-android 4.0 brings the `posthog` core 7.0, which isn't binary compatible with artifacts built against posthog-android 3.x. If your app also uses `posthog-server` older than 2.25.0, or another plugin or library built on posthog-android 3.x, it fails at runtime with errors such as `NoSuchMethodError`. Upgrade `posthog-server` to 2.25.0 or later. See [`posthog-server`](https://github.com/PostHog/posthog-android/blob/main/MIGRATION.md#posthog-server) in the Android guide.

### Breaking API changes

These all fail at compile time unless noted otherwise.

#### `getFeatureFlagResult(sendEvent:)` is now `sendFeatureFlagEvent:`

The parameter is also now `bool?`. See [the default change](#getfeatureflagresult-follows-your-config) below.

```dart
// Before
await Posthog().getFeatureFlagResult('my-flag', sendEvent: false);

// After
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: false);
```

#### `PostHogConfig.apiKey` is removed

Read `projectToken` instead. The constructor already takes the token as its first argument.

```dart
// Before
final token = config.apiKey;

// After
final token = config.projectToken;
```

#### `com.posthog.posthog.API_KEY` is removed

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

#### `Posthog().enable()` and `disable()` are removed

```dart
// Before
await Posthog().disable();
await Posthog().enable();

// After
await Posthog().optOut();
await Posthog().optIn();
```

#### `PostHogConfig.sendFeatureFlagEvents` is removed

```dart
// Before
config.sendFeatureFlagEvents = false;

// After
config.sendFeatureFlagEvent = false;
```

#### `Posthog().getFeatureFlagPayload()` is removed

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

#### `PostHogSessionReplayConfig.debouncerDelay` is removed

```dart
// Before
config.sessionReplayConfig.debouncerDelay = const Duration(seconds: 2);

// After
config.sessionReplayConfig.throttleDelay = const Duration(seconds: 2);
```

#### `PostHogDataMode.cellular` is removed

It always behaved like `any`, so sending does not change.

```dart
// Before
config.dataMode = PostHogDataMode.cellular;

// After
config.dataMode = PostHogDataMode.any;
```

#### `toMap()` and `PostHogFeatureFlagResult.fromMap()` are removed

They serialized the internal platform-channel format and have no replacement. `toMap()` is gone from `PostHogConfig`, `PostHogBootstrapConfig`, `PostHogLogsConfig`, `PostHogRageClickConfig`, `PostHogSessionReplayConfig`, `PostHogErrorTrackingConfig` and `PostHogExceptionStepsConfig`. To build a result, for example in a test, call the `PostHogFeatureFlagResult` constructor, which stays public.

#### `beforeSend` callbacks are synchronous

`BeforeSendCallback` is now `PostHogEvent? Function(PostHogEvent)`, and `BeforeSendLogCallback` is `PostHogLogRecord? Function(PostHogLogRecord)`. An `async` callback, or one declared to return `FutureOr<PostHogEvent?>`, is a compile error. Load what it needs ahead of time and read it synchronously.

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

#### Platform interface changes

These affect only code that calls, extends or fakes `PosthogFlutterPlatformInterface`, `PosthogFlutterIO` or `PosthogFlutterWeb` directly, such as test mocks. `Posthog().optIn()` and `optOut()` are unaffected.

- `enable()` and `disable()` are now `optIn()` and `optOut()`.
- `getFeatureFlagPayload()` is removed.
- `getFeatureFlagResult({required String key, bool sendEvent = true})` is now `getFeatureFlagResult({required String key, bool? sendFeatureFlagEvent})`.
- `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException` take an `options` map.
- `captureAi()` is new. The base class throws `UnimplementedError` unless you override it.
- `isFeatureEnabled()` takes `defaultValue`.
- `reloadFeatureFlags()` returns a `Future<PostHogFeatureFlagsLoaded>`.
- `setAppLanguage(String? language)` is new. The base class does nothing unless you override it.
- `registerOptions(Map<String, Object?> options)` and `unregisterOptions(String key)` are new. The base class throws `UnimplementedError` unless you override them.
- `OnFeatureFlagsCallback` now receives a `PostHogFeatureFlagsLoaded`: `void Function(PostHogFeatureFlagsLoaded loaded)` instead of `void Function()`.

```dart
// Before
@override
Future<void> disable() async {}

// After
@override
Future<void> optOut() async {}
```

#### `PostHogConfig.onFeatureFlags` is removed

Call `Posthog().onFeatureFlags()` before `setup()`, which also covers the first load. The callback receives a `PostHogFeatureFlagsLoaded`, with `flags`, `variants` and `errorsLoading`, and `reloadFeatureFlags()` now returns a `Future<PostHogFeatureFlagsLoaded>`.

```dart
// Before
final config = PostHogConfig('<project_token>', onFeatureFlags: () {
  // ...
});
// or
config.onFeatureFlags = () {
  // ...
};
await Posthog().setup(config);

// After
Posthog().onFeatureFlags((loaded) {
  if (!loaded.errorsLoading) {
    // Use loaded.variants
  }
});
await Posthog().setup(config);
```

### Behavior changes

#### Events go to capture v1

**This is a silent change if you use a reverse proxy or self-host.** On iOS, macOS, Android, Windows and Linux, events go to `/i/v1/analytics/events` instead of `/batch/`, and `captureAi` events go to `/i/v1/ai/events`. PostHog Cloud and the managed reverse proxy already serve the new paths. Most apps upgrade without code changes, and nothing here produces a compile error.

| Platform | Sent by | 6.0 |
| --- | --- | --- |
| iOS and macOS | posthog-ios 4.x | capture v1 |
| Android | posthog-android 4.x | capture v1 |
| Windows and Linux | posthog_flutter's own Dart client | capture v1 |
| Web | the posthog-js your app loads | unchanged |

Web doesn't move to capture v1 in this release. It keeps posthog-js and its current endpoints. On web, `options` are sent as the legacy option properties, and `captureAi` sends nothing.

For the changes every capture v1 SDK shares, such as event options, limits and per-event results, see [Upgrading to capture v1 SDKs](https://posthog.com/docs/libraries/capture-v1). On iOS, macOS and Android, capture v1 comes from the native SDKs, so the Capture v1 sections of the [iOS](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#capture-v1) and [Android](https://github.com/PostHog/posthog-android/blob/main/MIGRATION.md#endpoints) guides apply there too. Windows and Linux are covered [below](#capture-v1-on-windows-and-linux).

On every platform except web, an event's properties are now the SDK's, then registered properties, then the ones you pass, so your value wins over the SDK's for that event. In 5.x, the SDK's values won.

`$lib` and `$lib_version` are the exception on every platform except web: the SDK fills them as a pair after all of the above. If `$lib` is missing or empty, the SDK sets both, replacing a `$lib_version` you passed on its own. If `$lib` names another library, the SDK leaves both as you set them and doesn't add its own version.

On every platform except web, a registered `process_person_profile: false`, set with `registerOptions()` or as the `$process_person_profile` property with `register()`, also reaches `identify`, `alias`, `group` and `setPersonProperties`. PostHog accepts the `$identify`, `$create_alias` and `$groupidentify` events and then drops them with an ingestion warning, and the SDK doesn't report it. A `$set` event is kept, but the person isn't updated. In 5.x, the SDK replaced a registered `$process_person_profile` with its own value, so it had no effect. In 6.0 it also applies to other events after `identify` or with `PostHogPersonProfiles.always`, which then don't change the person profile. They are still linked to the person and billed as identified events. To keep identifying, pass the option on the call. A `$process_person_profile` property you pass loses to a registered option, so use the option:

```dart
await Posthog().registerOptions({'process_person_profile': false});

await Posthog().identify(
  userId: 'user-123',
  userProperties: {'plan': 'pro'},
  options: {'process_person_profile': true},
);
```

If you registered `false` to skip person profiles for anonymous users, remove it: `PostHogPersonProfiles.identifiedOnly`, the default, already does that and still lets `identify` create the person. To create no person profiles at all, set `personProfiles` to `PostHogPersonProfiles.never` instead. The SDK then skips these calls on the device.

On web, posthog-js replaces a registered `$process_person_profile` with its own value, so a registered `false` has no effect there.

##### Checklist

You need to change code if your app does any of these:

- sends events to a self-hosted PostHog or a reverse proxy that doesn't serve `/i/v1/analytics/events` and `/i/v1/ai/events`
- sends events through a reverse proxy set up from PostHog's proxy guides before 29 October 2026, which strips `Authorization`
- sends events through a proxy that redirects capture requests, other than with a 307 or 308 to the same origin as `host`
- identifies users with a distinct ID over 200 UTF-8 bytes, such as a JWT
- captures events whose name is over 200 UTF-8 bytes
- sets `projectToken` to a personal API key (`phx_...`)
- reads `$session_id` or `$window_id` from the raw request body, for example in a proxy
- relies on a `Retry-After` longer than 30 seconds
- sets `$cookieless_mode`, `$ignore_sent_at` or `$product_tour_id` to a value PostHog can't read, such as `"maybe"`
- on iOS, macOS or Android, filters insights, cohorts or actions on the `$feature_flag_response` of `$feature_flag_called` for a missing flag, such as `null`, `""` or `false` (see [Feature flag payloads](#feature-flag-payloads))
- registers or passes a property with the same key as one the SDK sets, such as `$os` or `$is_identified`, and expects the SDK's value to win
- passes `$lib` without `$lib_version`, or `$lib_version` without `$lib`
- on iOS and macOS, sends `null` inside a nested map and expects it to arrive as `null`
- on Android, sends lists with `null` elements and expects them removed
- on any platform except web, drops the event's `options` in `beforeSend` by returning a new `PostHogEvent` or replacing `event.options`
- alerts on the SDK's debug log lines, whose text changed on every platform except web
- on Windows or Linux, calls `exit()` without awaiting the calls before it or `Posthog().close()`
- on any platform except web, registers `process_person_profile: false` and still calls `identify`, `alias`, `group` or `setPersonProperties`

##### Reverse proxies and self-hosting

Before you upgrade, make your own proxy:

- forward `/i/v1/analytics/events` and `/i/v1/ai/events`
- pass `Authorization` (the project token, sent as `Bearer <token>`), every `PostHog-*` header, `Content-Type`, `Content-Encoding` and `User-Agent` through unchanged. PostHog answers `401` without `Authorization` and `400` without the others, and the batch is dropped.
- if your proxy strips other credentials, keep `Authorization` values that start with `Bearer phc_`, `Bearer phs_` or `Bearer phx_`, plus the exact `Bearer <key>` of an older key without a prefix
- accept request bodies up to 20 MB. AI requests are often larger than 1 MB, the default limit in nginx and ingress-nginx.
- pass PostHog's response body through unchanged, because a 2xx whose body isn't PostHog's `{"results": {...}}` drops the events instead of retrying them

PostHog's managed reverse proxy already does this and needs no change. A proxy set up from PostHog's [proxy guides](https://posthog.com/docs/advanced/proxy) before 29 October 2026 strips `Authorization`, so PostHog answers `401` and the events are dropped. Update it from the current guide.

The SDK doesn't fall back to `/batch/`. On iOS, macOS, Android, Windows and Linux, a 404 is retried, events stay queued until the route is served, and the SDK prints one warning, also without `debug`. Other statuses that aren't retried, such as 401, 403 or 405, drop the batch. Web keeps posthog-js, which doesn't send to these routes. For iOS and Android details, see the [iOS](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#hosts-without-capture-v1) and [Android](https://github.com/PostHog/posthog-android/blob/main/MIGRATION.md#hosts-without-capture-v1) guides.

#### Feature flag payloads

On iOS, macOS and Android, a malformed (such as a plain-text `hello`), empty or whitespace-only payload from `getFeatureFlagResult()` is now `null` instead of the raw string. On Android, a JSON `null` payload is also `null` instead of the string `"null"`.

On iOS and macOS, string values in `PostHogBootstrapConfig.featureFlagPayloads`, such as `"123"`, stay strings instead of being decoded to numbers or booleans.

A flag whose variant is an empty string reads as disabled on iOS, macOS, Android, Windows and Linux, as it already did on web. `isFeatureEnabled()` returns `false`, with or without `defaultValue`, `getFeatureFlagResult()` and `getAllFeatureFlags()` return `enabled: false`, `onFeatureFlags` listeners and `reloadFeatureFlags()` leave the flag out, and so does `$active_feature_flags` on captured events. `variant`, `getFeatureFlag()` and the event's `$feature/<key>` property still return `""`. PostHog no longer accepts empty variants for new flags, so only flags created earlier through the API, MCP or Terraform are affected. `/flags` still returns `enabled: true` for them, and other PostHog SDKs can still report them as enabled, so rename the variant before you upgrade.

On iOS, macOS and Android, `$feature_flag_called` for a missing flag now leaves out `$feature_flag_response`. 5.x sent `null` on iOS and macOS, and on Android `""` from `getFeatureFlag()` and `false` from `isFeatureEnabled()`. Insights, cohorts and actions that filter on `$feature_flag_response` being `null`, `""` or `false` to find missing flags stop matching new events without any error, so use an `is not set` filter instead. See [`$feature_flag_response` for a missing flag](https://github.com/PostHog/posthog-android/blob/main/MIGRATION.md#feature_flag_response-for-a-missing-flag) in the Android guide.

#### `beforeSend` on iOS, macOS and Android

**This is a silent change.** Callbacks now get the event the native SDK built, including its system properties, such as `$device_type` and `$session_id`, registered properties and options, such as the `process_person_profile: false` the SDK adds while person processing is off. Their changes are final. In 5.x they saw only the properties and options you passed, so a callback that loops over or strips every property now also touches the SDK's. `PostHogEvent` also has `uuid`, `distinctId` and `timestamp`, set on every platform except web. A callback can change the distinct ID and timestamp, and the event keeps its uuid.

**Person processing is decided before the callbacks run.** In 5.x, a callback that removed `$set` prevented a person profile. Now the event is still person-processed, and so are later events. Return `null` to drop an event that must not create a profile. A callback that adds `$set` to an anonymous event must also set the `process_person_profile: true` option.

Nested maps are `Map<String, dynamic>`, and a non-empty list of maps is `List<Map<String, dynamic>>`. Any other list is `List<dynamic>`, even a `List<String>` you passed to `capture`, so cast its items instead of the list.

The `PostHogEvent` the callbacks return replaces the event's options. A callback that returns a new `PostHogEvent`, or replaces `event.options`, without the options it got drops them, including `process_person_profile: false`, which turns person processing on for that event. Copy `event.options` to the event you return.

A Dart callback that sets the distinct ID to an empty or whitespace-only string keeps the SDK's distinct ID for that event.

Events the native SDK captures itself don't go through Dart callbacks. Use `PosthogFlutterPlugin.addBeforeSend` in Swift or Kotlin for those. A native hook that sets the distinct ID to an empty or whitespace-only string drops the event.

#### Null values on iOS, macOS and Android

On iOS and macOS, a `null` value inside a nested map, including one a `beforeSend` callback returns, is now left out of the event instead of being sent as `null`. A list keeps a `null` element at its position, and a map left empty is sent as `{}`. `$set`, `$set_once` and `$group_set` still send `null` values, so you can still clear a person or group property. See [Null event properties](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#null-event-properties) in the iOS guide.

On Android, a `null` element in a list is now sent as `null` at its position instead of being removed, which moved later elements to lower indexes in 5.x. A map entry whose value is `null` is still left out.

#### Lifecycle events on iOS and macOS

`Application Installed`, `Application Updated` and `Application Opened` no longer include `version` and `build`. Update insights, cohorts and filters that use them to `$app_version` and `$app_build`. Android still sends them.

#### `$locale` and `$app_language`

`$locale` now means the device's language, with its region, on iOS, Android, macOS, Windows and Linux: `de-CH` instead of `de` on iOS, macOS, Windows and Linux. On Android it no longer follows a per-app language or `Locale.setDefault()`. On older Android versions, Hebrew, Indonesian and Yiddish values also change from legacy codes, such as `in-ID` to `id-ID`. If a user picks a language for your app in iOS or macOS Settings, the system reports that language as the first preferred language, so `$locale` follows it.

Update cohorts, insights and actions that match `$locale`: a filter on `$locale = de` stops matching `de-CH`. To keep matching a language, use a regex such as `^de(-|$)`, because "contains" also matches `en-DE`. Events already stored keep the old values. Feature flags aren't affected: the SDK doesn't send `$locale` or `$app_language` with flag requests, so flags only see these if you set them as person properties yourself.

The new `$app_language` property is the language your app shows. `PosthogObserver` reports the locale exactly as your `MaterialApp` resolved it every time a route changes. An app that doesn't declare `supportedLocales` reports `en-US`, and one declaring `Locale('en')` reports `en`, so use a regex such as `^en(-|$)` to match English. Native detection is off because Flutter apps translate in Dart. If you translate outside `Localizations`, don't use the observer, or want to send another value, call `Posthog().setAppLanguage('de')`. Web doesn't send `$app_language` yet, because posthog-js doesn't support it. To send it there now, call `Posthog().register(r'$app_language', 'de')`.

#### Network reachability on iOS and macOS

A path that needs user action, such as a VPN waiting for a password, counts as reachable, and queues pause while cellular data is off for the app. Events captured in the first 100 ms after setup may leave out `$network_wifi` and `$network_cellular`. Events still on disk from a `posthog-ios` 2.x SDK are deleted instead of sent.

#### Personal API keys

A personal API key (`phx_...`) in `projectToken` now skips `setup()` with one log line, so the SDK doesn't start and the key is never sent. Use your project token (`phc_...`).

#### Capture v1 on Windows and Linux

Windows and Linux send events through posthog_flutter's own Dart client, not a native SDK. This section covers what the native guides cover for the other platforms.

##### Event validation

Capture v1 checks each event on its own and drops only the invalid ones, so the rest of the batch is delivered.

- The SDK drops an event with an empty event name before sending it, as in 5.x. With `debug` on, it logs the drop.
- PostHog drops an event whose name is over 200 UTF-8 bytes. Legacy capture had no limit on event name length.
- PostHog drops an event whose distinct ID is over 200 UTF-8 bytes. Legacy capture shortened the ID to 200 characters and kept the event. If you identify users with a long ID, such as a JWT or a long email address, shorten or hash it before you upgrade. Otherwise every event for that user is dropped.
- `identify` with an empty or whitespace-only distinct ID is ignored, as in 5.x.
- A `NaN` or infinite `double` property value is removed and the event is still sent, as in 5.x. Inside a list, it's sent as `null`.
- A lone UTF-16 surrogate, such as a string cut in the middle of an emoji, becomes U+FFFD and the event is sent. This covers the event name, distinct ID, `$session_id`, `$window_id`, properties and options, the IDs passed to `identify`, `alias` and `group`, and the person and group properties sent to `/flags`. The SDK keeps each ID as you passed it and repairs only what it sends. In 5.x, legacy capture rejected the whole batch for a lone surrogate anywhere in it. iOS, macOS and Android already send the event with U+FFFD in place of each lone surrogate.
- The SDK doesn't report these drops to your code. With `debug` on, it logs how many events PostHog dropped and why (see [Logs](#logs)).

##### Property precedence

An event's properties are the SDK's, then registered properties, then the event's own, so your value now wins for that event. In 5.x, the SDK's values won.
`$lib` and `$lib_version` are the exception: the SDK fills them as a pair after all of the above. If `$lib` is missing or empty, the SDK sets both, replacing a `$lib_version` you passed on its own. If `$lib` names another library, the SDK leaves both as you set them and doesn't add its own version.
`beforeSend` runs after that merge and sees the result.

A registered or passed `$session_id` that is a non-empty string replaces the SDK's session ID, which can detach events from their session.

##### Session and window IDs

Capture v1 sends `$session_id` and `$window_id` as top-level `session_id` and `window_id` fields, not as properties.
The SDK moves them out of `properties` for you.

- A string value, including an empty string, is sent unchanged.
- Any other value is removed and not sent. With `debug` on, the SDK logs a warning that names the key and the value's JSON type, never the value.
- A `null` value counts as unset and is removed without a warning.

In PostHog, the events still have `$session_id` and `$window_id`.

##### Event options

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
- To set an option for every event, register it with `Posthog().registerOptions({'cookieless_mode': true})` and remove it with `unregisterOptions`. An event's own options win over registered ones, and `reset()` clears them. Registering its legacy option property, such as `Posthog().register(r'$cookieless_mode', true)`, still works.
- A registered `process_person_profile: false` also reaches identity calls; see [Events go to capture v1](#events-go-to-capture-v1).
- Person processing is sent as the `process_person_profile: false` option only while it's off, instead of a `$process_person_profile` property on every event.
- Person processing is decided before `beforeSend` runs, as on iOS, macOS and Android. A callback that adds `$set` to an anonymous event must also set the `process_person_profile: true` option.
- Events still queued on disk by 5.x are sent to capture v1 after the update, with their legacy option properties moved to options.

**Review your `beforeSend` callbacks for the new event shape.** On Windows and Linux, `beforeSend` sees the options the SDK adds, including `process_person_profile: false`. A callback that returns a new `PostHogEvent` or replaces `event.options` without that key turns person processing on for that event. A legacy option property that a callback adds doesn't replace an option that is already set. `beforeSend` doesn't see `$identify`, `$create_alias`, `$groupidentify` or `$feature_flag_called`.

`$exception_steps` is added to `$exception` events before `beforeSend` runs, so a callback can read or remove it. Steps recorded while a callback runs, and an event a callback renames to `$exception`, don't get them.

##### Retries

- The SDK retries network errors and 404, 408, 429, 500, 502, 503 and 504 responses. Other statuses drop the batch, such as a 402 when you're over your billing limit. A product quota, such as for AI events, instead drops only those events inside a 2xx. 5.x retried 408, 429, every 5xx and 3xx responses, and didn't retry 404.
- When the response asks to retry only some events, the SDK keeps those events queued and removes the rest.
- After a failed send, the wait before the next one doubles from 1 second up to 30 seconds, with up to 25% random jitter. Retries have no limit: queued events stay until they're delivered or a full queue drops the oldest. In 5.x, a failed batch was retried up to 3 times, 3 seconds apart, within the same flush.
- A `Retry-After` header is a floor under that wait, capped at 30 seconds. In 5.x it had no cap.
- A 2xx response without PostHog's per-event results drops the batch. It isn't retried, because PostHog may have stored some of the events.
- A request times out after 10 seconds without progress, and an AI request after 60 seconds. In 5.x, a request timed out after 10 seconds in total.

##### Redirects

The SDK follows a 307 or 308 redirect only to the origin of `host` (same scheme, host and port), at most 5 times, and resends the same body and headers.
Any other redirect drops the batch.
In 5.x, no redirect was followed and the batch stayed queued.
If a proxy redirects capture requests to another host, point `host` at the final host.

##### Batches and size limits

- A request carries at most `maxBatchSize` events and 5 MiB. The SDK sends as soon as 5 MiB of events is queued, even before `flushAt` is reached. In 5.x, batches were limited by event count only.
- A larger event is sent alone.
- A `413` for a batch of more than one event halves `maxBatchSize` and `flushAt`, and the events are sent again in smaller batches. A `413` for a single event drops it.
- The SDK doesn't limit the size of an analytics event, as in 5.x.

##### AI events

- `captureAi` events have their own on-disk queue of up to `captureAiMaxQueueSize` events (100 by default) and 50 MiB, and the oldest are dropped first. `maxQueueSize` doesn't apply.
- An event over `captureAiMaxEventBytes` (8 MiB plus 64 KiB by default) is dropped, and `captureAi` returns `null`. You can only lower the limit.
- AI requests are gzipped unless you set `captureAiCompression` to `PostHogCompression.none`. `compression` doesn't apply.
- AI requests time out after 60 seconds without progress, or `captureAiTimeout`.
- AI events use `flushAt` and `maxBatchSize`, like other events.
- `flush()` and `close()` also send AI events, and AI events left on disk are sent after the next `setup()`.
- PostHog drops an event sent with `captureAi` whose name doesn't start with `$ai_`. With `debug` on, the SDK logs a warning for it. `capture` never sends events to the AI endpoint.

##### Logs

All of these log only with `debug` on, except the 404 warning.

- One line per batch reports the events PostHog dropped, with their reasons, and the repeated-uuid copies it dropped, for example `Capture /i/v1/analytics/events dropped 1 of 20 events for good (event_name_too_long: 1) and 0 repeated-uuid copies.` 5.x had no such line.
- A failed flush logs `Error while flushing PostHog /i/v1/analytics/events` or `/i/v1/ai/events` and the error, without the response body. In 5.x the line was `Error while flushing PostHog` and the error included the response body. Update any log-based alerts that match the old text.
- The debug log no longer includes the properties of captured and sent events. To inspect events, use `beforeSend`.

##### Timestamps and IDs

- An event's timestamp is taken before `beforeSend` runs, and a callback can change it.
- Timestamps are UTC with 3 or 6 fractional digits, as in 5.x. The SDK doesn't check for future timestamps.
- Event uuids, request IDs and anonymous distinct IDs are UUID v7. You can't set an event's uuid, so events never repeat one.

##### Writes to disk

An event is no longer on disk when `capture`, `screen`, `captureException`, `captureFeatureView`, `captureFeatureInteraction`, `identify`, `alias`, `group` or `setPersonProperties` returns, only when the returned future completes. One you didn't await can be lost if the app crashes or calls `exit()` right after. Await the call, or `Posthog().close()`, before `exit()`. Only `close()` also covers events the SDK captures itself, such as `$feature_flag_called`. An `identify` not awaited before `exit()` can lose its `$identify` event for good, because the new ID is already saved. `close()` can now take up to 4 seconds, and a later `setup()` waits for the queue's file work.

#### `getFeatureFlagResult()` follows your config

**This is a silent change with no compile error.** When you omit `sendFeatureFlagEvent`, `getFeatureFlagResult()` now uses `PostHogConfig.sendFeatureFlagEvent` instead of always capturing `$feature_flag_called`. This matches `getFeatureFlag()` and `isFeatureEnabled()`.

It only affects apps that set `config.sendFeatureFlagEvent = false`. Those apps stop sending `$feature_flag_called` from `getFeatureFlagResult()`, so insights and experiments that rely on that event can receive less data. To keep the event for a call:

```dart
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: true);
```

On web, `PostHogConfig.sendFeatureFlagEvent` is not applied to posthog-js, so an omitted value keeps the posthog-js default, which captures the event. Pass `sendFeatureFlagEvent: false` to suppress it on web.

### New features

- An `options` argument on `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException`, and `PostHogEvent.options` in `beforeSend`. `process_person_profile`, `cookieless_mode`, `disable_skew_correction` and `product_tour_id` win over their legacy option properties (`$process_person_profile`, `$cookieless_mode`, `$ignore_sent_at` and `$product_tour_id`). Other keys are sent unchanged. On web, known keys are sent as those legacy option properties and other keys are dropped. On web, `process_person_profile` has no effect, and the options of `identify`, `setPersonProperties`, `alias` and `group` are dropped.
- `Posthog().registerOptions()` and `unregisterOptions()`, to send capture options such as `cookieless_mode` with every following event. An event's own options win over registered ones, and `reset()` clears them. On web, known keys are registered as their legacy option properties and other keys are dropped.
- `isFeatureEnabled(defaultValue:)`, returned when the flag has no value because flags haven't loaded, the request failed or the key doesn't exist. A flag that has a value always wins.
- `PostHogEvent.uuid`, `distinctId` and `timestamp` in `beforeSend`, set on every platform except web. A callback can change the distinct ID and timestamp.
- `captureAi` for `$ai_*` events. It returns the event's UUID, or `null` when the event isn't admitted. On web it sends nothing and returns `null`.
- `Posthog().onFeatureFlags()` to get notified after every feature flags load. It returns a `PostHogFeatureFlagsSubscription` you can `unsubscribe()`. You can register it before `WidgetsFlutterBinding.ensureInitialized()`, but other SDK calls, including `setup()`, are skipped with a warning until the binding is initialized.
- `$app_language` and `Posthog().setAppLanguage()`. See [`$locale` and `$app_language`](#locale-and-app_language).
- `PosthogFlutterPlugin.addBeforeSend` in Swift and Kotlin, to filter or edit events the native SDK captures itself, such as crashes, app lifecycle and `$feature_flag_called` events.
- `PostHogConfig.captureAiCompression`, `captureAiMaxQueueSize`, `captureAiTimeout` and `captureAiMaxEventBytes` for `captureAi` requests. They don't apply on web.

### Upgrade checklist

- [ ] Use the Flutter SDK 3.41 or later on every platform, and make sure Swift Package Manager is on for iOS and macOS.
- [ ] Don't upgrade yet if you embed Flutter as an iOS or macOS add-to-app module.
- [ ] Raise iOS to 15.0 and macOS to 11.0 in your Xcode projects, and in any `Podfile` you keep.
- [ ] Rename `com.posthog.posthog.API_KEY` to `com.posthog.posthog.PROJECT_TOKEN` in `AndroidManifest.xml` and `Info.plist`.
- [ ] Use Xcode 26 or later.
- [ ] If you run your own reverse proxy or self-host, serve `/i/v1/analytics/events` and `/i/v1/ai/events` first.
- [ ] Shorten or hash distinct IDs over 200 UTF-8 bytes.
- [ ] Make `beforeSend` callbacks, including `PostHogLogsConfig.beforeSend`, synchronous.
- [ ] Review your `beforeSend` callbacks for the new event shape, which includes the SDK's properties and options on every platform except web, and for person processing decided before they run.
- [ ] Replace `PostHogConfig.onFeatureFlags` with `Posthog().onFeatureFlags()` before `setup()`.
- [ ] Update cohorts, insights and actions that match `$locale`, which now includes the region. Use `$app_language` for the language your app shows.
- [ ] Move anything that reads `version` or `build` on iOS and macOS lifecycle events to `$app_version` and `$app_build`.
- [ ] Change filters on `$feature_flag_response` being `null`, `""` or `false` for missing flags to `is not set`.
- [ ] If you set `sendFeatureFlagEvent = false`, check whether anything relies on `$feature_flag_called` from `getFeatureFlagResult()`.
- [ ] Add `sendFeatureFlagEvent: false` wherever you replace `getFeatureFlagPayload()`.
- [ ] Fix the remaining compile errors using the sections above, including any test fakes of the platform classes.

### Rolling back to 5.x

If you ship 6.0 and then go back to 5.x, events still queued on the device are sent by 5.x to `/batch/`, which doesn't read capture options. This applies on iOS, macOS, Windows and Linux:

- Events that 6.0 marked as personless (`process_person_profile: false`) are processed as person events.
- Options such as `cookieless_mode` passed through `options` or `registerOptions()` are lost.
- AI events queued by 6.0 in their own queue are never sent.
