# Migrate the Flutter SDK from 5.x.x to 6.0.0

The Flutter SDK 6.x.x sends every event on iOS, macOS, Android, Windows, and Linux to the [capture v1](https://posthog.com/docs/api/capture-v1) endpoints, `/i/v1/analytics/events` and `/i/v1/ai/events`. On the web, it uses the JavaScript Web SDK, which stays on legacy capture.

Use the top right copy page button to work through this with your agents.

You don't need to make every change on the day you upgrade your SDK. Required changes fall in these categories:

- **Before you upgrade**: you should make these changes before you upgrade your SDK to 6.x.x.
- **During your upgrade**: These are changes that you need to make in the same PR that upgrades your SDK version.
- **Follow ups**: These are changes that can come in follow up PRs because 6.x.x has limited backward compatibility for methods that are to be deprecated.

## Checklist

Read the checklist first, then the sections that apply to you.

**Before you upgrade**

- [ ] You build with a Flutter SDK older than 3.41.0, on any platform → [Update Flutter and Xcode](#update-flutter-and-xcode)
- [ ] You build for iOS or macOS with an Xcode older than 26 → [Update Flutter and Xcode](#update-flutter-and-xcode)
- [ ] Your iOS deployment target is below 15.0 or your macOS deployment target is below 11.0, in your Xcode projects or in a `Podfile` you keep → [Raise deployment targets](#raise-deployment-targets)
- [ ] You build for iOS or macOS with Swift Package Manager off → [Use Swift Package Manager](#use-swift-package-manager)
- [ ] You embed Flutter in an iOS app as an add-to-app module → use Flutter 3.50.0 or later, see [Use Swift Package Manager](#use-swift-package-manager)
- [ ] You use `posthog-server` older than 2.25.0 in your Android app → [Check native SDKs](#check-native-sdks)
- [ ] You send events through a reverse proxy that doesn't serve `/i/v1/analytics/events` and `/i/v1/ai/events` → [Prepare your proxy](#prepare-your-proxy)
- [ ] You send events through a reverse proxy set up from PostHog's proxy guides before 29 October 2026, which strips `Authorization` → [Prepare your proxy](#prepare-your-proxy)
- [ ] You send events through a proxy that redirects capture requests, other than with a 307 or 308 to the same origin as `host` → [Prepare your proxy](#prepare-your-proxy)
- [ ] You set `projectToken` to a personal API key (`phx_...`) → [Use a project token](#use-a-project-token)
- [ ] You identify users with a distinct ID over 200 UTF-8 bytes, such as a JWT → [Shorten long IDs](#shorten-long-ids)
- [ ] You capture events whose name is over 200 UTF-8 bytes → [Shorten long IDs](#shorten-long-ids)
- [ ] You have a feature flag with an empty-string variant → [Rename empty variants](#rename-empty-variants)

**During your upgrade**

- [ ] You get compile errors from APIs that 6.x.x removes → [Fix removed APIs](#fix-removed-apis)
- [ ] You replace `getFeatureFlagPayload()` and need `sendFeatureFlagEvent: false` on the new call → [Fix removed APIs](#fix-removed-apis)
- [ ] You set `PostHogConfig.onFeatureFlags` → [Replace onFeatureFlags](#replace-onfeatureflags)
- [ ] You set `com.posthog.posthog.API_KEY` in `AndroidManifest.xml` or `Info.plist` → [Rename the token key](#rename-the-token-key)
- [ ] You have `async` `beforeSend` callbacks, including `PostHogLogsConfig.beforeSend` → [Make beforeSend synchronous](#make-beforesend-synchronous)
- [ ] You call, extend, or fake the platform classes, such as in test fakes → [Update platform fakes](#update-platform-fakes)
- [ ] You set `beforeSend` callbacks on any platform except web → [Review beforeSend callbacks](#review-beforesend-callbacks)
- [ ] You drop the event's `options` in `beforeSend` on any platform except web, by returning a new `PostHogEvent` or replacing `event.options` → [Review beforeSend callbacks](#review-beforesend-callbacks)
- [ ] You register or pass a property with the same key as one the SDK sets, such as `$os` or `$is_identified`, and expect the SDK's value to win → [Check property precedence](#check-property-precedence)
- [ ] You pass `$lib` without `$lib_version`, or `$lib_version` without `$lib` → [Check property precedence](#check-property-precedence)
- [ ] You register `process_person_profile: false` on any platform except web and expect it to keep every event personless → [Check registered person processing](#check-registered-person-processing)
- [ ] You filter insights, cohorts, or actions on the `$feature_flag_response` of `$feature_flag_called` for a missing flag, such as `null`, `""`, or `false`, on iOS, macOS, or Android → [Update flag filters](#update-flag-filters)
- [ ] You set `sendFeatureFlagEvent = false` and rely on `$feature_flag_called` from `getFeatureFlagResult()` → [Check flag events](#check-flag-events)
- [ ] You send `null` inside a nested map on iOS or macOS and expect it to arrive as `null` → [Check null values](#check-null-values)
- [ ] You send lists with `null` elements on Android and expect them removed → [Check null values](#check-null-values)
- [ ] You read `version` or `build` on iOS or macOS lifecycle events → [Update lifecycle filters](#update-lifecycle-filters)
- [ ] You match `$locale` in cohorts, insights, or actions → [Update locale filters](#update-locale-filters)
- [ ] You read `$session_id` or `$window_id` from the raw request body, for example in a proxy → [Check dropped events](#check-dropped-events)
- [ ] You set `$cookieless_mode`, `$ignore_sent_at`, or `$product_tour_id` to a value PostHog can't read, such as `"maybe"` → [Check dropped events](#check-dropped-events)
- [ ] You rely on a `Retry-After` longer than 30 seconds → [Check retries](#check-retries)
- [ ] You alert on the SDK's debug log lines, whose text changed on every platform except web → [Update log alerts](#update-log-alerts)
- [ ] You call `exit()` on Windows or Linux without awaiting the calls before it or `Posthog().close()` → [Await before exit](#await-before-exit)

**Follow ups**

- [ ] You set legacy option properties such as `$process_person_profile` → [Move to event options](#move-to-event-options)
- [ ] You capture `$ai_` events with `capture()` → [Send AI events](#send-ai-events)

## Before you upgrade

### Update Flutter and Xcode

| Tool | 5.x.x | 6.x.x |
| --- | --- | --- |
| Flutter SDK | 3.27.0 | 3.41.0 |
| Xcode | Not set by the plugin | 26 or later |

posthog_flutter 6.x.x needs the Flutter SDK 3.41.0 or later on every platform. `flutter pub get` fails on an older Flutter, including in Android-only apps.

The declared Dart minimum (`>=3.6.0`) is unchanged. Flutter 3.41.0 ships a newer Dart, so that Dart is the real minimum.

posthog_flutter 6.x.x needs Xcode 26 or later. 5.x.x didn't set an Xcode minimum.

### Raise deployment targets

| Target | 5.x.x | 6.x.x |
| --- | --- | --- |
| iOS deployment target | 13.0 | 15.0 |
| macOS deployment target | 10.15 | 11.0 |
| Android `minSdkVersion` declared by the plugin | 21 | 23 |

On iOS and macOS, raise your app's deployment targets. A lower target fails the build.

Set **Minimum Deployments** for the `Runner` target in Xcode (**Runner > General > Minimum Deployments**). It sets `IPHONEOS_DEPLOYMENT_TARGET` and `MACOSX_DEPLOYMENT_TARGET`.

If you keep a `Podfile` for other plugins, raise its platform too:

```ruby
# ios/Podfile
platform :ios, '15.0'

# macos/Podfile
platform :osx, '11.0'
```

On Android, you have nothing to change.

`posthog-android` has required `minSdkVersion` 23 since 3.39.0, so an app on 21 or 22 already couldn't build with this plugin. The plugin now declares the same value.

### Use Swift Package Manager

posthog_flutter 6.x.x has no podspec. On iOS and macOS, it installs only through Swift Package Manager.

5.x.x installed through CocoaPods or Swift Package Manager. Only iOS and macOS builds need Swift Package Manager.

With Swift Package Manager off, `flutter build` exits with `Plugin posthog_flutter is only compatible with Swift Package Manager`.

1. Use Flutter 3.41.0 or later. The plugin's `Package.swift` depends on the `FlutterFramework` package, which Flutter generates starting with 3.41.0.
2. Turn Swift Package Manager on if it's off. It's on by default from Flutter 3.44.0. On 3.41.x to 3.43.x, or if you turned it off, run:

   ```sh
   flutter config --enable-swift-package-manager
   ```

3. Run your app. Flutter adds Swift Package Manager to the Xcode project on its own.

Other plugins that only support CocoaPods keep working. Flutter installs them through your `Podfile` and installs posthog_flutter as a Swift package. Keep the `Podfile` in that case.

If every plugin in your app supports Swift Package Manager, you can remove CocoaPods. This is optional. Follow [Flutter's steps](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers#how-to-remove-cocoapods-integration).

Add-to-app modules (`flutter create -t module`) on iOS need Flutter 3.50.0 or later:

- **On Flutter 3.50.0 or later.** Build the module with `flutter build swift-package`.
- **On earlier Flutter versions.** `flutter build swift-package` installs a module's plugins with CocoaPods and stops with `Unable to find a specification for 'posthog_flutter' depended upon by 'FlutterPluginRegistrant'`, since posthog_flutter has no podspec ([flutter/flutter#184590](https://github.com/flutter/flutter/issues/184590)). Stay on posthog_flutter 5.x.x, or use the other route.
- **The other route.** On Flutter 3.44.0 or later, you can embed Flutter in an iOS or macOS app from a Flutter app project (`flutter create`, not `-t module`). Follow Flutter's Swift Package Manager add-to-app steps for [iOS](https://docs.flutter.dev/add-to-app/ios/project-setup) or [macOS](https://docs.flutter.dev/add-to-app/macos/project-setup). This works with posthog_flutter 6.x.x.

### Check native SDKs

| Native SDK | 5.x.x | 6.x.x |
| --- | --- | --- |
| `posthog-ios` | `>= 3.92.3, < 4.0.0` | `>= 4.0.0, < 5.0.0` |
| `posthog-android` | `[3.75.0, 4.0.0)` | `[4.0.0, 5.0.0)` |

Don't add these native SDKs to your app separately at a different major version.

On Android, posthog-android 4.0.0 brings the `posthog` core 7.0.0. It isn't binary compatible with artifacts built against posthog-android 3.x.x.

If your app also uses `posthog-server` older than 2.25.0, or another plugin or library built on posthog-android 3.x.x, it fails at runtime with errors such as `NoSuchMethodError`. Upgrade `posthog-server` to 2.25.0 or later. See [`posthog-server`](https://github.com/PostHog/posthog-android/blob/main/MIGRATION.md#upgrade-posthog-server) in the Android guide.

### Prepare your proxy

On iOS, macOS, Android, Windows, and Linux, events go to `/i/v1/analytics/events` instead of `/batch/`, and `captureAi` events go to `/i/v1/ai/events`. Nothing here produces a compile error.

| Platform | Sent by | 6.x.x |
| --- | --- | --- |
| iOS and macOS | posthog-ios 4.x.x | capture v1 |
| Android | posthog-android 4.x.x | capture v1 |
| Windows and Linux | posthog_flutter's own Dart client | capture v1 |
| Web | the posthog-js your app loads | unchanged |

Web doesn't move to capture v1 in this release. It keeps posthog-js and its current endpoints, so posthog-js doesn't send to these routes.

PostHog Cloud and PostHog's managed reverse proxy already serve the new paths. The managed reverse proxy needs no change.

If you send events through your own reverse proxy, update it before you upgrade:

- **Forward both routes.** Forward `/i/v1/analytics/events` and `/i/v1/ai/events`.
- **Pass the headers through unchanged.** Pass `Authorization`, every `PostHog-*` header, `Content-Type`, `Content-Encoding`, and `User-Agent`. `Authorization` holds the project token, sent as `Bearer <token>`. PostHog answers `401` without `Authorization` and `400` without the others, and the batch is dropped.
- **Keep PostHog's credentials.** If your proxy strips other credentials, keep `Authorization` values that start with `Bearer phc_`, `Bearer phs_`, or `Bearer phx_`. Also keep the exact `Bearer <key>` of an older key without a prefix.
- **Accept request bodies up to 20 MB.** AI requests are often larger than 1 MB, the default limit in nginx and ingress-nginx.
- **Pass PostHog's response body through unchanged.** A 2xx whose body isn't PostHog's `{"results": {...}}` drops the events instead of retrying them.

A proxy set up from PostHog's [proxy guides](https://posthog.com/docs/advanced/proxy) before 29 October 2026 strips `Authorization`, so PostHog answers `401` and the events are dropped. Update it from the current guide.

The SDK doesn't fall back to `/batch/`. On iOS, macOS, Android, Windows, and Linux, these statuses decide what happens to a batch:

- **A 404.** The SDK retries it, and events stay queued until the route is served. The SDK prints one warning, also without `debug`.
- **Other statuses that aren't retried.** A status such as 401, 403, or 405 drops the batch.

On Windows and Linux, the SDK follows a 307 or 308 redirect only to the origin of `host`, at most 5 times. The origin is the same scheme, host, and port. The SDK resends the same body and headers.

Any other redirect drops the batch. In 5.x.x, no redirect was followed and the batch stayed queued. If a proxy redirects capture requests to another host, point `host` at the final host.

On iOS, macOS, and Android, capture v1 comes from the native SDKs. The capture v1 changes in the [iOS](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#during-your-upgrade) and [Android](https://github.com/PostHog/posthog-android/blob/main/MIGRATION.md#during-your-upgrade) guides apply there too.

For the changes every capture v1 SDK shares, such as event options, limits, and per-event results, see [Upgrading to capture v1 SDKs](https://posthog.com/docs/api/capture-v1).

### Use a project token

A personal API key (`phx_...`) in `projectToken` now skips `setup()` with one log line. The SDK doesn't start, and the key is never sent. Use your project token (`phc_...`).

### Shorten long IDs

On Windows and Linux, PostHog drops an event whose distinct ID is over 200 UTF-8 bytes. Legacy capture shortened the ID to 200 characters and kept the event.

If you identify users with a long ID, such as a JWT or a long email address, shorten or hash it before you upgrade. Otherwise every event for that user is dropped.

On Windows and Linux, PostHog also drops an event whose name is over 200 UTF-8 bytes. Legacy capture had no limit on event name length.

On iOS, macOS, and Android, the native SDKs send the events (see [Prepare your proxy](#prepare-your-proxy)).

### Rename empty variants

A flag whose variant is an empty string reads as disabled on iOS, macOS, Android, Windows, and Linux, as it already did on web.

| Call or property | Result for an empty variant |
| --- | --- |
| `isFeatureEnabled()` | `false`, with or without `defaultValue` |
| `getFeatureFlagResult()` and `getAllFeatureFlags()` | `enabled: false` |
| `onFeatureFlags` listeners and `reloadFeatureFlags()` | Leave the flag out |
| `$active_feature_flags` on captured events | Leaves the flag out |
| `variant`, `getFeatureFlag()`, and the event's `$feature/<key>` property | Still `""` |

PostHog no longer accepts empty variants for new flags, so only flags created earlier through the API, MCP, or Terraform are affected.

`/flags` still returns `enabled: true` for them, and other PostHog SDKs can still report them as enabled. Rename the variant before you upgrade.

## During your upgrade

### Fix removed APIs

6.x.x removes these APIs. Each one is a compile error.

| Removed | Use instead |
| --- | --- |
| The `sendEvent:` parameter of `getFeatureFlagResult()` | `sendFeatureFlagEvent:` |
| `PostHogConfig.apiKey` | `projectToken` |
| `Posthog().enable()` and `disable()` | `Posthog().optIn()` and `optOut()` |
| `PostHogConfig.sendFeatureFlagEvents` | `sendFeatureFlagEvent` |
| `Posthog().getFeatureFlagPayload()` | `getFeatureFlagResult()` and its `payload` |
| `PostHogSessionReplayConfig.debouncerDelay` | `throttleDelay` |
| `PostHogDataMode.cellular` | `PostHogDataMode.any` |
| `toMap()` and `PostHogFeatureFlagResult.fromMap()` | Nothing |
| `PostHogConfig.onFeatureFlags` | `Posthog().onFeatureFlags()` |

The `sendFeatureFlagEvent:` parameter is also now `bool?` (see [Check flag events](#check-flag-events)).

The `PostHogConfig` constructor already takes the token as its first argument.

`PostHogDataMode.cellular` always behaved like `any`, so sending doesn't change.

`toMap()` and `PostHogFeatureFlagResult.fromMap()` serialized the internal platform-channel format.

To move to `Posthog().onFeatureFlags()`, see [Replace onFeatureFlags](#replace-onfeatureflags).

Rename the `sendEvent:` parameter:

```dart
// Before
await Posthog().getFeatureFlagResult('my-flag', sendEvent: false);

// After
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: false);
```

Read `projectToken` instead of `apiKey`:

```dart
// Before
final token = config.apiKey;

// After
final token = config.projectToken;
```

Call `optOut()` and `optIn()`:

```dart
// Before
await Posthog().disable();
await Posthog().enable();

// After
await Posthog().optOut();
await Posthog().optIn();
```

Set `sendFeatureFlagEvent`:

```dart
// Before
config.sendFeatureFlagEvents = false;

// After
config.sendFeatureFlagEvent = false;
```

`getFeatureFlagPayload()` never captured `$feature_flag_called` on iOS, macOS, Android, Windows, or Linux. Pass `sendFeatureFlagEvent: false` to keep it that way. Without it, the replacement call captures the event when your config allows it:

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

Set `throttleDelay`:

```dart
// Before
config.sessionReplayConfig.debouncerDelay = const Duration(seconds: 2);

// After
config.sessionReplayConfig.throttleDelay = const Duration(seconds: 2);
```

Use `PostHogDataMode.any`:

```dart
// Before
config.dataMode = PostHogDataMode.cellular;

// After
config.dataMode = PostHogDataMode.any;
```

`toMap()` is gone from `PostHogConfig`, `PostHogBootstrapConfig`, `PostHogLogsConfig`, `PostHogRageClickConfig`, `PostHogSessionReplayConfig`, `PostHogErrorTrackingConfig`, and `PostHogExceptionStepsConfig`.

To build a result, for example in a test, call the `PostHogFeatureFlagResult` constructor, which stays public.

### Replace onFeatureFlags

`PostHogConfig.onFeatureFlags` is removed. Call `Posthog().onFeatureFlags()` before `setup()`, which also covers the first load.

- **The callback.** It receives a `PostHogFeatureFlagsLoaded`, with `flags`, `variants`, and `errorsLoading`. It runs after every feature flags load.
- **The subscription.** `Posthog().onFeatureFlags()` returns a `PostHogFeatureFlagsSubscription` you can `unsubscribe()`.
- **Reloads.** `reloadFeatureFlags()` now returns a `Future<PostHogFeatureFlagsLoaded>`.
- **Before the binding.** You can register the callback before `WidgetsFlutterBinding.ensureInitialized()`. Other SDK calls, including `setup()`, are skipped with a warning until the binding is initialized.

Register the callback, then call `setup()`:

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

### Rename the token key

`com.posthog.posthog.API_KEY` is removed. Apps that start the SDK from `AndroidManifest.xml` on Android, or `Info.plist` on iOS and macOS, must rename the key to `com.posthog.posthog.PROJECT_TOKEN`.

This doesn't fail at build time. With only the old key, the SDK logs an error and doesn't start, so the app sends no data.

Rename the key in `AndroidManifest.xml`:

```xml
<!-- AndroidManifest.xml, before -->
<meta-data android:name="com.posthog.posthog.API_KEY" android:value="<YOUR_PROJECT_TOKEN>" />

<!-- AndroidManifest.xml, after -->
<meta-data android:name="com.posthog.posthog.PROJECT_TOKEN" android:value="<YOUR_PROJECT_TOKEN>" />
```

Rename the key in `Info.plist`:

```xml
<!-- Info.plist, before -->
<key>com.posthog.posthog.API_KEY</key>
<string><YOUR_PROJECT_TOKEN></string>

<!-- Info.plist, after -->
<key>com.posthog.posthog.PROJECT_TOKEN</key>
<string><YOUR_PROJECT_TOKEN></string>
```

### Make beforeSend synchronous

`BeforeSendCallback` is now `PostHogEvent? Function(PostHogEvent)`, and `BeforeSendLogCallback` is `PostHogLogRecord? Function(PostHogLogRecord)`.

An `async` callback, or one declared to return `FutureOr<PostHogEvent?>`, is a compile error. Load what the callback needs ahead of time and read it synchronously:

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

### Update platform fakes

These changes affect only code that calls, extends, or fakes `PosthogFlutterPlatformInterface`, `PosthogFlutterIO`, or `PosthogFlutterWeb` directly, such as test mocks. `Posthog().optIn()` and `optOut()` are unaffected.

| Member | Change |
| --- | --- |
| `enable()` and `disable()` | Now `optIn()` and `optOut()` |
| `getFeatureFlagPayload()` | Removed |
| `getFeatureFlagResult()` | New parameters |
| `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group`, and `captureException` | Take an `options` map |
| `captureAi()` | New |
| `isFeatureEnabled()` | Takes `defaultValue` |
| `reloadFeatureFlags()` | New return type |
| `setAppLanguage()` | New |
| `registerOptions()` and `unregisterOptions()` | New |
| `OnFeatureFlagsCallback` | New parameter |

`getFeatureFlagResult({required String key, bool sendEvent = true})` is now `getFeatureFlagResult({required String key, bool? sendFeatureFlagEvent})`.

The base class `captureAi()` throws `UnimplementedError` unless you override it. So do `registerOptions(Map<String, Object?> options)` and `unregisterOptions(String key)`.

The base class `setAppLanguage(String? language)` does nothing unless you override it.

`reloadFeatureFlags()` returns a `Future<PostHogFeatureFlagsLoaded>`.

`OnFeatureFlagsCallback` now receives a `PostHogFeatureFlagsLoaded`. It's `void Function(PostHogFeatureFlagsLoaded loaded)` instead of `void Function()`.

Rename the overrides in your fakes:

```dart
// Before
@override
Future<void> disable() async {}

// After
@override
Future<void> optOut() async {}
```

### Review beforeSend callbacks

Review your `beforeSend` callbacks for the new event shape. Nothing here produces a compile error.

On iOS, macOS, and Android, callbacks now get the event the native SDK built. Their changes are final. The event includes these:

- **System properties.** Properties such as `$device_type` and `$session_id`.
- **Registered properties.** The properties you registered.
- **Options.** Options such as the `process_person_profile: false` the SDK adds while person processing is off.

In 5.x.x, callbacks saw only the properties and options you passed. A callback that loops over or strips every property now also touches the SDK's.

On Windows and Linux, `beforeSend` sees the options the SDK adds, including `process_person_profile: false`. These rules apply on every platform except web:

- **Options.** The `PostHogEvent` the callbacks return replaces the event's options. A callback that returns a new `PostHogEvent`, or replaces `event.options`, without the options it got drops them. That includes `process_person_profile: false`, which turns person processing on for that event. Copy `event.options` to the event you return.
- **Person processing.** It's decided before the callbacks run. A callback that adds `$set` to an anonymous event must also set the `process_person_profile: true` option.
- **New fields.** `PostHogEvent` has `uuid`, `distinctId`, and `timestamp`, set on every platform except web. A callback can change the distinct ID and timestamp, and the event keeps its uuid.

These rules apply on iOS, macOS, and Android:

- **Removed `$set`.** In 5.x.x, a callback that removed `$set` prevented a person profile. Now the event is still person-processed, and so are later events. Return `null` to drop an event that must not create a profile.
- **Collection types.** Nested maps are `Map<String, dynamic>`, and a non-empty list of maps is `List<Map<String, dynamic>>`. Any other list is `List<dynamic>`, even a `List<String>` you passed to `capture`, so cast its items instead of the list.
- **Empty distinct IDs.** A Dart callback that sets the distinct ID to an empty or whitespace-only string keeps the SDK's distinct ID for that event.
- **Native events.** Events the native SDK captures itself don't go through Dart callbacks. Use `PosthogFlutterPlugin.addBeforeSend` in Swift or Kotlin to filter or edit those, such as crashes, app lifecycle, and `$feature_flag_called` events. A native hook that sets the distinct ID to an empty or whitespace-only string drops the event.

These rules apply on Windows and Linux:

- **Legacy option properties.** A legacy option property that a callback adds doesn't replace an option that is already set.
- **Events callbacks don't see.** `beforeSend` doesn't see `$identify`, `$create_alias`, `$groupidentify`, or `$feature_flag_called`.
- **Exception steps.** `$exception_steps` is added to `$exception` events before `beforeSend` runs, so a callback can read or remove it. Steps recorded while a callback runs, and an event a callback renames to `$exception`, don't get them.
- **Timestamps.** An event's timestamp is taken before `beforeSend` runs, and a callback can change it.

### Check property precedence

On every platform except web, an event's properties are the SDK's, then registered properties, then the ones you pass. Your value wins over the SDK's for that event. In 5.x.x, the SDK's values won.

`$lib` and `$lib_version` are the exception on every platform except web. The SDK fills them as a pair after all of the above.

| You set | The SDK sends |
| --- | --- |
| No `$lib`, or an empty one | Its own `$lib` and `$lib_version` |
| A `$lib` that names another library | Both as you set them |

With no `$lib`, or an empty one, the SDK replaces a `$lib_version` you passed on its own. With a `$lib` that names another library, it doesn't add its own version.

On Windows and Linux, `beforeSend` runs after that merge and sees the result.

On Windows and Linux, a registered or passed `$session_id` that is a non-empty string replaces the SDK's session ID. This can detach events from their session.

### Check registered person processing

On every platform except web, a registered `process_person_profile: false` now applies to your events. You register it with `registerOptions()`, or as the `$process_person_profile` property with `register()`.

- **Other events.** The registered value also applies to events after `identify` or with `PostHogPersonProfiles.always`. Those events then don't change the person profile. They are still linked to the person and billed as identified events.
- **Identity events.** The registered value doesn't apply to `$identify`, `$create_alias`, `$merge_dangerously`, `$groupidentify`, `$set`, and `$set_once`. With person processing off, PostHog drops the first four and ignores the person update of `$set` and `$set_once`, so a registered `false` would stop `identify`, `alias`, `group`, and `setPersonProperties` from working. A value you pass on the call still applies.
- **5.x.x.** The SDK replaced a registered `$process_person_profile` with its own value, so it had no effect.
- **Web.** posthog-js replaces a registered `$process_person_profile` with its own value, so a registered `false` has no effect there.

If you registered `false` to skip person profiles for anonymous users, remove it. `PostHogPersonProfiles.identifiedOnly`, the default, already does that and still lets `identify` create the person.

To create no person profiles at all, set `personProfiles` to `PostHogPersonProfiles.never` instead. The SDK then skips these calls on the device.

### Check flag values

- **Malformed payloads on iOS, macOS, and Android.** A malformed, empty, or whitespace-only payload from `getFeatureFlagResult()` is now `null` instead of the raw string. A plain-text `hello` is a malformed payload.
- **JSON `null` payloads on Android.** A JSON `null` payload is also `null` instead of the string `"null"`.
- **Bootstrap payloads on iOS and macOS.** String values in `PostHogBootstrapConfig.featureFlagPayloads`, such as `"123"`, stay strings instead of being decoded to numbers or booleans.
- **Default values.** `isFeatureEnabled(defaultValue:)` returns `defaultValue` when the flag has no value. That happens when flags haven't loaded, the request failed, or the key doesn't exist. A flag that has a value always wins.

### Update flag filters

On iOS, macOS, and Android, `$feature_flag_called` for a missing flag now leaves out `$feature_flag_response`.

| Platform | 5.x.x sent |
| --- | --- |
| iOS and macOS | `null` |
| Android | `""` from `getFeatureFlag()` and `false` from `isFeatureEnabled()` |

Insights, cohorts, and actions that filter on `$feature_flag_response` being `null`, `""`, or `false` to find missing flags stop matching new events without any error. Use an `is not set` filter instead.

See [Check flag events](https://github.com/PostHog/posthog-android/blob/main/MIGRATION.md#check-flag-events) in the Android guide.

### Check flag events

When you omit `sendFeatureFlagEvent`, `getFeatureFlagResult()` now uses `PostHogConfig.sendFeatureFlagEvent` instead of always capturing `$feature_flag_called`. This matches `getFeatureFlag()` and `isFeatureEnabled()`. It produces no compile error.

It only affects apps that set `config.sendFeatureFlagEvent = false`. Those apps stop sending `$feature_flag_called` from `getFeatureFlagResult()`, so insights and experiments that rely on that event can receive less data.

To keep the event for a call, pass `sendFeatureFlagEvent: true`:

```dart
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: true);
```

On web, `PostHogConfig.sendFeatureFlagEvent` isn't applied to posthog-js. An omitted value keeps the posthog-js default, which captures the event. Pass `sendFeatureFlagEvent: false` to suppress it on web.

### Check null values

On iOS and macOS, a `null` value inside a nested map is now left out of the event instead of being sent as `null`. That includes one a `beforeSend` callback returns.

- **Lists.** A list keeps a `null` element at its position.
- **Empty maps.** A map left empty is sent as `{}`.
- **Person and group properties.** `$set`, `$set_once`, and `$group_set` still send `null` values, so you can still clear a person or group property.

See [Check null properties](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#check-null-properties) in the iOS guide.

On Android, a `null` element in a list is now sent as `null` at its position instead of being removed. In 5.x.x, the removal moved later elements to lower indexes. A map entry whose value is `null` is still left out.

### Update lifecycle filters

On iOS and macOS, `Application Installed`, `Application Updated`, and `Application Opened` no longer include `version` and `build`. Update insights, cohorts, and filters that use them to `$app_version` and `$app_build`. Android still sends them.

### Update locale filters

`$locale` now means the device's language, with its region, on iOS, Android, macOS, Windows, and Linux.

- **iOS, macOS, Windows, and Linux.** `$locale` is `de-CH` instead of `de`.
- **Android.** `$locale` no longer follows a per-app language or `Locale.setDefault()`.
- **Older Android versions.** Hebrew, Indonesian, and Yiddish values also change from legacy codes, such as `in-ID` to `id-ID`.
- **App languages on iOS and macOS.** If a user picks a language for your app in iOS or macOS Settings, the system reports that language as the first preferred language, so `$locale` follows it.

Update cohorts, insights, and actions that match `$locale`. A filter on `$locale = de` stops matching `de-CH`.

To keep matching a language, use a regex such as `^de(-|$)`, since "contains" also matches `en-DE`. Events already stored keep the old values.

Feature flags aren't affected. The SDK doesn't send `$locale` or `$app_language` with flag requests, so flags only see these if you set them as person properties yourself.

The new `$app_language` property is the language your app shows:

- **The observer.** `PosthogObserver` reports the locale exactly as your `MaterialApp` resolved it every time a route changes.
- **Reported values.** An app that doesn't declare `supportedLocales` reports `en-US`, and one declaring `Locale('en')` reports `en`. Use a regex such as `^en(-|$)` to match English.
- **Native detection.** It's off, since Flutter apps translate in Dart.
- **Your own value.** If you translate outside `Localizations`, don't use the observer, or want to send another value, call `Posthog().setAppLanguage('de')`.
- **Web.** Web doesn't send `$app_language` yet, since posthog-js doesn't support it. To send it there now, call `Posthog().register(r'$app_language', 'de')`.

### Check dropped events

Windows and Linux send events through posthog_flutter's own Dart client, not a native SDK. On iOS, macOS, and Android, the native guides linked in [Prepare your proxy](#prepare-your-proxy) cover these changes.

Capture v1 checks each event on its own and drops only the invalid ones, so the rest of the batch is delivered. On Windows and Linux:

- **Empty event names.** The SDK drops an event with an empty event name before sending it, as in 5.x.x. With `debug` on, it logs the drop.
- **Long names and IDs.** PostHog drops an event whose name or distinct ID is over 200 UTF-8 bytes (see [Shorten long IDs](#shorten-long-ids)).
- **Empty distinct IDs.** `identify` with an empty or whitespace-only distinct ID is ignored, as in 5.x.x.
- **`NaN` and infinite values.** A `NaN` or infinite `double` property value is removed and the event is still sent, as in 5.x.x. Inside a list, it's sent as `null`.
- **Option values.** Option values are sent as given. PostHog drops an event whose option value it can't read.
- **Reporting.** The SDK doesn't report these drops to your code. With `debug` on, it logs how many events PostHog dropped and why (see [Update log alerts](#update-log-alerts)).

On Windows and Linux, a lone UTF-16 surrogate, such as a string cut in the middle of an emoji, becomes U+FFFD and the event is sent. The repair covers these values:

- **Event fields.** The event name, distinct ID, `$session_id`, `$window_id`, properties, and options.
- **Identity calls.** The IDs passed to `identify`, `alias`, and `group`.
- **Flag requests.** The person and group properties sent to `/flags`.

The SDK keeps each ID as you passed it and repairs only what it sends. In 5.x.x, legacy capture rejected the whole batch for a lone surrogate anywhere in it. iOS, macOS, and Android already send the event with U+FFFD in place of each lone surrogate.

Capture v1 sends `$session_id` and `$window_id` as top-level `session_id` and `window_id` fields, not as properties. On Windows and Linux, the SDK moves them out of `properties` for you, by the value's type:

- **A string.** The SDK sends it unchanged, including an empty string.
- **`null`.** It counts as unset, and the SDK removes it without a warning.
- **Any other value.** The SDK removes it and doesn't send it. With `debug` on, the SDK logs a warning that names the key and the value's JSON type, never the value.

In PostHog, the events still have `$session_id` and `$window_id`.

### Check retries

On Windows and Linux, retries change:

| Behavior | 5.x.x | 6.x.x |
| --- | --- | --- |
| Statuses retried | 408, 429, every 5xx, and 3xx responses, but not 404 | Network errors and 404, 408, 429, 500, 502, 503, and 504 responses |
| Wait between sends | 3 seconds | 1 to 30 seconds |
| Retry limit | 3 times | None |
| `Retry-After` | No cap | Capped at 30 seconds |
| Timeout | 10 seconds in total | 10 seconds without progress |

In 6.x.x, other statuses drop the batch, such as a 402 when you're over your billing limit.

In 6.x.x, the wait doubles after each failed send, from 1 second up to 30 seconds, with up to 25% random jitter. `Retry-After` is a floor under the wait, capped at 30 seconds.

In 5.x.x, a failed batch was retried up to 3 times, within the same flush. In 6.x.x, queued events stay until they're delivered or a full queue drops the oldest.

In 6.x.x, an AI request times out after 60 seconds without progress.

The response decides what the SDK keeps:

- **Product quotas.** A product quota, such as for AI events, drops only those events inside a 2xx.
- **Partial retries.** When the response asks to retry only some events, the SDK keeps those events queued and removes the rest.
- **Responses without results.** A 2xx response without PostHog's per-event results drops the batch. It isn't retried, since PostHog may have stored some of the events.

### Check batch sizes

On Windows and Linux, batches have a size limit:

- **The limit.** A request carries at most `maxBatchSize` events and 5 MiB. In 5.x.x, batches were limited by event count only.
- **Early sends.** The SDK sends as soon as 5 MiB of events is queued, even before `flushAt` is reached.
- **Larger events.** A larger event is sent alone.
- **A `413` for a batch.** A `413` for a batch of more than one event halves `maxBatchSize` and `flushAt`, and the events are sent again in smaller batches.
- **A `413` for one event.** A `413` for a single event drops it.
- **Analytics events.** The SDK doesn't limit the size of an analytics event, as in 5.x.x.

### Check timestamps and IDs

On Windows and Linux:

- **Timestamps.** Timestamps are UTC with 3 or 6 fractional digits, as in 5.x.x. The SDK doesn't check for future timestamps.
- **IDs.** Event uuids, request IDs, and anonymous distinct IDs are UUID v7. You can't set an event's uuid, so events never repeat one.

### Update log alerts

On Windows and Linux, all of these log only with `debug` on, except the 404 warning.

- **Dropped events.** One line per batch reports the events PostHog dropped, with their reasons, and the repeated-uuid copies it dropped. For example, `Capture /i/v1/analytics/events dropped 1 of 20 events for good (event_name_too_long: 1) and 0 repeated-uuid copies.` 5.x.x had no such line.
- **Failed flushes.** A failed flush logs `Error while flushing PostHog /i/v1/analytics/events` or `/i/v1/ai/events` and the error, without the response body. In 5.x.x the line was `Error while flushing PostHog` and the error included the response body. Update any log-based alerts that match the old text.
- **Event properties.** The debug log no longer includes the properties of captured and sent events. To inspect events, use `beforeSend`.

### Await before exit

On Windows and Linux, an event is no longer on disk when one of these calls returns, only when the returned future completes:

- `capture`
- `screen`
- `captureException`
- `captureFeatureView`
- `captureFeatureInteraction`
- `identify`
- `alias`
- `group`
- `setPersonProperties`

An event you didn't await can be lost if the app crashes or calls `exit()` right after. Await the call, or `Posthog().close()`, before `exit()`.

Only `close()` also covers events the SDK captures itself, such as `$feature_flag_called`.

An `identify` not awaited before `exit()` can lose its `$identify` event for good, since the new ID is already saved.

`close()` can now take up to 4 seconds, and a later `setup()` waits for the queue's file work.

### Check queued events

- **Events queued by 5.x.x on Windows and Linux.** They're sent to capture v1 after the update, with their legacy option properties moved to options.
- **Events queued by `posthog-ios` 2.x.x.** If an app updates straight from a `posthog-ios` 2.x.x SDK, events that 2.x.x left on disk are deleted instead of sent. Distinct ID, anonymous ID, groups, and cached feature flags carry over. Events queued by 5.x.x aren't affected.

### Check network reachability

On iOS and macOS, reachability changes:

- **Paths that need user action.** A path that needs user action, such as a VPN waiting for a password, counts as reachable.
- **Cellular data.** Queues pause while cellular data is off for the app.
- **Network properties.** Events captured in the first 100 ms after setup may leave out `$network_wifi` and `$network_cellular`.

### Plan a rollback

If you ship 6.0.0 and then go back to 5.x.x, events still queued on the device are sent by 5.x.x to `/batch/`, which doesn't read capture options. This applies on every platform except web:

- **Personless events.** Events that 6.0.0 marked as personless (`process_person_profile: false`) are processed as person events.
- **Options.** Options such as `cookieless_mode` passed through `options` or `registerOptions()` are lost.
- **AI events.** 5.x.x doesn't send AI events queued by 6.x.x in their own queue. They stay on the device, and 6.x.x sends them after you update again.
- **Registered options.** Options registered with `registerOptions()` don't apply to events 5.x.x captures. They're kept, and apply again after you update to 6.x.x.

## Follow ups

### Move to event options

`capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group`, and `captureException` take an `options` argument. `beforeSend` gets them in `PostHogEvent.options`.

Each option wins over its legacy option property. The legacy option properties are the `$`-prefixed properties legacy capture reads as settings, and they still work.

| Legacy option property | Option |
| --- | --- |
| `$process_person_profile` | `process_person_profile` |
| `$cookieless_mode` | `cookieless_mode` |
| `$ignore_sent_at` | `disable_skew_correction` |
| `$product_tour_id` | `product_tour_id` |

Other option keys are sent unchanged.

To send an option with every following event, register it with `Posthog().registerOptions({'cookieless_mode': true})`. Remove it with `unregisterOptions()`. An event's own options win over registered ones, and `reset()` clears them.

A registered `process_person_profile` doesn't apply to identity calls (see [Check registered person processing](#check-registered-person-processing)).

On Windows and Linux, the SDK's own Dart client handles the legacy option properties:

- **Legacy option properties.** When the event is sent, the SDK removes each one from `properties` and uses it for its option.
- **Precedence.** An option you pass or set in `beforeSend` wins over its legacy option property. A `null` option counts as unset, so the legacy option property fills it.
- **Registered legacy properties.** Registering a legacy option property, such as `Posthog().register(r'$cookieless_mode', true)`, still works.
- **Person processing.** It's sent as the `process_person_profile: false` option only while it's off, instead of a `$process_person_profile` property on every event.

Web keeps the legacy option properties:

| On web | Result |
| --- | --- |
| Known keys in `options` | Sent as their legacy option properties |
| Known keys in `registerOptions()` | Registered as their legacy option properties |
| Other keys | Dropped |
| `process_person_profile` | No effect |
| The options of `identify`, `setPersonProperties`, `alias`, and `group` | Dropped |

### Send AI events

`captureAi` sends `$ai_*` events to `/i/v1/ai/events`. It returns the event's UUID, or `null` when the event isn't admitted.

On web, `captureAi` sends nothing and returns `null`.

`PostHogConfig.captureAiCompression`, `captureAiMaxQueueSize`, `captureAiTimeout`, and `captureAiMaxEventBytes` set up `captureAi` requests. They don't apply on web.

On Windows and Linux, AI events have their own queue:

- **The queue.** `captureAi` events have their own on-disk queue of up to `captureAiMaxQueueSize` events (100 by default) and 50 MiB. The oldest are dropped first. `maxQueueSize` doesn't apply.
- **Large events.** An event over `captureAiMaxEventBytes` (8 MiB plus 64 KiB by default) is dropped, and `captureAi` returns `null`. You can only lower the limit.
- **Compression.** AI requests are gzipped unless you set `captureAiCompression` to `PostHogCompression.none`. `compression` doesn't apply.
- **Timeouts.** AI requests time out after 60 seconds without progress, or `captureAiTimeout`.
- **Batches.** AI events use `flushAt` and `maxBatchSize`, like other events.
- **Flushes.** `flush()` and `close()` also send AI events. AI events left on disk are sent after the next `setup()`.
- **Event names.** PostHog drops an event sent with `captureAi` whose name doesn't start with `$ai_`. With `debug` on, the SDK logs a warning for it. `capture` never sends events to the AI endpoint.
