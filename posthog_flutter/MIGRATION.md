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

### Native SDKs

<!--
PENDING, not on this branch yet. PR #673 (which contains #649) moves the plugin to posthog-ios 4.x and
posthog-android 4.x. Neither is released. When it merges, replace this comment with a section covering:
- Xcode 26 required.
- onFeatureFlags receives, and reloadFeatureFlags() returns, PostHogFeatureFlagsLoaded.
- Capture v1 endpoints and what reverse proxies must forward.
- iOS and Android: malformed, empty or whitespace-only flag payloads become null. iOS: bootstrapped string payloads stay strings.
- iOS and macOS: lifecycle events stop sending version and build.
- iOS: reachability moves to NWPathMonitor; events queued on disk by a 2.x SDK are deleted.
Check each against the plugin before documenting it.
-->

The native dependency ranges are unchanged by this release: `posthog-ios` `>= 3.92.3, < 4.0.0` and `posthog-android` `[3.72.9, 4.0.0)`.

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

## Behavior changes

### `getFeatureFlagResult()` follows your config

**This is a silent change with no compile error.** When you omit `sendFeatureFlagEvent`, `getFeatureFlagResult()` now uses `PostHogConfig.sendFeatureFlagEvent` instead of always capturing `$feature_flag_called`. This matches `getFeatureFlag()` and `isFeatureEnabled()`.

It only affects apps that set `config.sendFeatureFlagEvent = false`. Those apps stop sending `$feature_flag_called` from `getFeatureFlagResult()`, so insights and experiments that rely on that event can receive less data. To keep the event for a call:

```dart
await Posthog().getFeatureFlagResult('my-flag', sendFeatureFlagEvent: true);
```

On web, `PostHogConfig.sendFeatureFlagEvent` is not applied to posthog-js, so an omitted value keeps the posthog-js default, which captures the event. Pass `sendFeatureFlagEvent: false` to suppress it on web.

## Upgrade checklist

- [ ] Use Flutter 3.41 or later and make sure Swift Package Manager is on.
- [ ] Don't upgrade yet if you embed Flutter as an iOS or macOS add-to-app module.
- [ ] Raise iOS to 15.0 and macOS to 11.0 in your Xcode projects, and in any `Podfile` you keep.
- [ ] Rename `com.posthog.posthog.API_KEY` to `com.posthog.posthog.PROJECT_TOKEN` in `AndroidManifest.xml` and `Info.plist`.
- [ ] If you set `sendFeatureFlagEvent = false`, check whether anything relies on `$feature_flag_called` from `getFeatureFlagResult()`.
- [ ] Add `sendFeatureFlagEvent: false` wherever you replace `getFeatureFlagPayload()`.
- [ ] Fix the remaining compile errors using the sections above, including any test fakes of the platform classes.
