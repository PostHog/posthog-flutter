# Migrating from posthog_flutter 5.x to 6.0

## Requirements

| | 5.x | 6.0 |
| --- | --- | --- |
| iOS deployment target | 13.0 | 15.0 |
| macOS deployment target | 10.15 | 11.0 |
| Android `minSdkVersion` declared by the plugin | 21 | 23 |

The Dart (`>=3.6.0`) and Flutter (`>=3.27.0`) minimums are unchanged.

### iOS and macOS

Raise your app's deployment targets. A lower target fails the build.

```ruby
# ios/Podfile
platform :ios, '15.0'

# macos/Podfile
platform :osx, '11.0'
```

Also set `IPHONEOS_DEPLOYMENT_TARGET` and `MACOSX_DEPLOYMENT_TARGET` in your Xcode projects, including when you build with Swift Package Manager.

### Android

`posthog-android` has required `minSdkVersion` 23 since 3.39.0, so an app on 21 or 22 already could not build with this plugin. The plugin now declares the same value, and you have nothing to change.

### Native SDKs

<!--
PENDING, not on this branch yet. PR #673 (which contains #649) moves the plugin to posthog-ios 4.x and
posthog-android 4.x. Neither is released. When it merges, replace this comment with a section covering:
- Xcode 26 required.
- posthog-ios 4.0 is not published to CocoaPods, so `s.dependency 'PostHog', '>= 4.0.0'` cannot resolve: state what CocoaPods apps must do.
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

- [ ] Raise iOS to 15.0 and macOS to 11.0 in your Podfiles and Xcode projects.
- [ ] Rename `com.posthog.posthog.API_KEY` to `com.posthog.posthog.PROJECT_TOKEN` in `AndroidManifest.xml` and `Info.plist`.
- [ ] If you set `sendFeatureFlagEvent = false`, check whether anything relies on `$feature_flag_called` from `getFeatureFlagResult()`.
- [ ] Add `sendFeatureFlagEvent: false` wherever you replace `getFeatureFlagPayload()`.
- [ ] Fix the remaining compile errors using the sections above, including any test fakes of the platform classes.
