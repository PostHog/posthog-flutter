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
| `posthog-android` | `[3.72.9, 4.0.0)` | `[4.0.0, 5.0.0)` |
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

### Platform interface changes

These affect only code that calls, extends or fakes `PosthogFlutterPlatformInterface`, `PosthogFlutterIO` or `PosthogFlutterWeb` directly, such as test mocks. `Posthog().optIn()` and `optOut()` are unaffected.

- `enable()` and `disable()` are now `optIn()` and `optOut()`.
- `getFeatureFlagPayload()` is removed.
- `getFeatureFlagResult({required String key, bool sendEvent = true})` is now `getFeatureFlagResult({required String key, bool? sendFeatureFlagEvent})`.

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

**This is a silent change if you use a reverse proxy or self-host.** On iOS, macOS, Android, Windows and Linux, events go to `/i/v1/analytics/events` instead of `/batch/`, and `captureAi` events go to `/i/v1/ai/events`. Web keeps using posthog-js and its current endpoints. PostHog Cloud and the managed reverse proxy already serve the new paths.

Before you upgrade, make your own proxy:

- forward `/i/v1/analytics/events` and `/i/v1/ai/events`
- pass `Authorization` (the project token, sent as `Bearer <token>`), every `PostHog-*` header, `Content-Type`, `Content-Encoding` and `User-Agent` through unchanged
- accept request bodies up to 20 MB

If you ignore this on Windows and Linux, a 404 is retried, events stay queued, and the SDK prints one warning, also without `debug`. See the [iOS](https://github.com/PostHog/posthog-ios/blob/main/MIGRATION.md#hosts-without-capture-v1) and [Android](https://github.com/PostHog/posthog-android/blob/main/docs/migration-3.x-to-4.0.md#hosts-without-capture-v1) guides for those platforms.

### Feature flag payloads

On iOS, macOS and Android, a malformed, empty or whitespace-only payload from `getFeatureFlagResult()` is now `null` instead of the raw string. On Android, a JSON `null` payload is also `null` instead of the string `"null"`.

On iOS and macOS, string values in `PostHogBootstrapConfig.featureFlagPayloads`, such as `"123"`, stay strings instead of being decoded to numbers or booleans.

### `beforeSend` on iOS, macOS and Android

**This is a silent change.** Callbacks now get the event the native SDK built, including its system properties, such as `$device_type` and `$session_id`, and registered properties. Their changes are final. In 5.x they saw only the properties you passed, so a callback that loops over or strips every property now also touches the SDK's. `PostHogEvent` also has `uuid`, `distinctId` and `timestamp`, set on every platform except web.

Events the native SDK captures itself don't go through Dart callbacks. Use `PosthogFlutterPlugin.addBeforeSend` in Swift or Kotlin for those.

### Lifecycle events on iOS and macOS

`Application Installed`, `Application Updated` and `Application Opened` no longer include `version` and `build`. Update insights, cohorts and filters that use them to `$app_version` and `$app_build`. Android still sends them.

### Network reachability on iOS and macOS

A path that needs user action, such as a VPN waiting for a password, counts as reachable, and queues pause while cellular data is off for the app. Events captured in the first 100 ms after setup may leave out `$network_wifi` and `$network_cellular`. Events still on disk from a `posthog-ios` 2.x SDK are deleted instead of sent.

### Windows and Linux

- **Property order:** an event's properties are the SDK's, then registered properties, then the event's own, so your value now wins for that event. `beforeSend` runs after that merge, except that `$lib` and `$lib_version` always come from the `PostHog-Sdk-Info` header.
- **Person processing:** it's sent as the `process_person_profile: false` option only while it's off, instead of a `$process_person_profile` property on every event.
- **`beforeSend` and person processing:** person processing is decided before the callbacks run. A callback that adds `$set` to an anonymous event must also set the `process_person_profile: true` option.
- **Redirects:** only same-origin 307 and 308 redirects are followed. Any other redirect drops the batch.
- **Retries:** a failed batch waits 1 second, doubling up to 30 seconds with ±25% jitter, instead of retrying within the same flush. `Retry-After` is a floor under that wait, capped at 30 seconds.
- **Timestamps:** an event's timestamp is taken before `beforeSend` runs.
- **AI queue:** `captureAi` events have their own on-disk queue of up to `captureAiMaxQueueSize` events (100 by default) and 50 MiB. An event over `captureAiMaxEventBytes` (8 MiB plus 64 KiB by default) is dropped.

### `getFeatureFlagResult()` follows your config

**This is a silent change with no compile error.** When you omit `sendFeatureFlagEvent`, `getFeatureFlagResult()` now uses `PostHogConfig.sendFeatureFlagEvent` instead of always capturing `$feature_flag_called`. This matches `getFeatureFlag()` and `isFeatureEnabled()`.

It only affects apps that set `config.sendFeatureFlagEvent = false`. Those apps stop sending `$feature_flag_called` from `getFeatureFlagResult()`, so insights and experiments that rely on that event can receive less data. To keep the event for a call:

```dart
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: true);
```

On web, `PostHogConfig.sendFeatureFlagEvent` is not applied to posthog-js, so an omitted value keeps the posthog-js default, which captures the event. Pass `sendFeatureFlagEvent: false` to suppress it on web.

## New features

- An `options` argument on `capture`, `screen`, `identify`, `setPersonProperties`, `alias`, `group` and `captureException`, and `PostHogEvent.options` in `beforeSend`. `process_person_profile`, `cookieless_mode`, `disable_skew_correction` and `product_tour_id` win over their legacy `$` properties. On web, known keys are sent as those legacy properties and other keys are dropped.
- `captureAi` for `$ai_*` events. It returns the event's UUID, or `null` when the event isn't admitted. On web it sends nothing and returns `null`.

## Upgrade checklist

- [ ] Use Flutter 3.41 or later and make sure Swift Package Manager is on.
- [ ] Don't upgrade yet if you embed Flutter as an iOS or macOS add-to-app module.
- [ ] Raise iOS to 15.0 and macOS to 11.0 in your Xcode projects, and in any `Podfile` you keep.
- [ ] Rename `com.posthog.posthog.API_KEY` to `com.posthog.posthog.PROJECT_TOKEN` in `AndroidManifest.xml` and `Info.plist`.
- [ ] Use Xcode 26 or later.
- [ ] If you run your own reverse proxy or self-host, serve `/i/v1/analytics/events` and `/i/v1/ai/events` first.
- [ ] Update `onFeatureFlags` callbacks to take a `PostHogFeatureFlagsLoaded`.
- [ ] Move anything that reads `version` or `build` on iOS and macOS lifecycle events to `$app_version` and `$app_build`.
- [ ] If you set `sendFeatureFlagEvent = false`, check whether anything relies on `$feature_flag_called` from `getFeatureFlagResult()`.
- [ ] Add `sendFeatureFlagEvent: false` wherever you replace `getFeatureFlagPayload()`.
- [ ] Fix the remaining compile errors using the sections above, including any test fakes of the platform classes.
