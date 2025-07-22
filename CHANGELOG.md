## Next

## 5.1.0

- feat: surveys for iOS ([#188](https://github.com/PostHog/posthog-flutter/pull/188))

## 5.0.0

- chore: support flutter web wasm builds ([#112](https://github.com/PostHog/posthog-flutter/pull/112))

### Breaking changes

- Dart min version 3.3.0
- Flutter min version 3.19.0

## 4.11.0

- chore: Session Replay - GA ([#178](https://github.com/PostHog/posthog-flutter/pull/178))

## 4.10.8

- chore: pin the iOS SDK to 3.22.x ([#177](https://github.com/PostHog/posthog-flutter/pull/177))

## 4.10.7

- fix: import dart io only on non-web platforms ([#176](https://github.com/PostHog/posthog-flutter/pull/176))

## 4.10.6

- fix: check if image size is valid before sending snapshot ([#174](https://github.com/PostHog/posthog-flutter/pull/174))

## 4.10.5

- chore: linux and windows NoOp support ([#173](https://github.com/PostHog/posthog-flutter/pull/173))

## 4.10.4

- fix: dispose recorder if masking is disabled ([#166](https://github.com/PostHog/posthog-flutter/pull/166))

## 4.10.3

- chore: pin the iOS SDK to 3.x.x ([#162](https://github.com/PostHog/posthog-flutter/pull/162))

## 4.10.2

- chore: pin the iOS SDK to 3.19.x ([#157](https://github.com/PostHog/posthog-flutter/pull/157))

## 4.10.1

- fix: isSessionReplayActive returns false by default for flutter web ([#158](https://github.com/PostHog/posthog-flutter/pull/158))

## 4.10.0

- chore: add support for session replay manual masking with the PostHogMaskWidget widget ([#153](https://github.com/PostHog/posthog-flutter/pull/153))

## 4.9.4

- fix: solve masks out of sync when moving too fast ([#147](https://github.com/PostHog/posthog-flutter/pull/147))

## 4.9.3

- chore: pin the iOS SDK to 3.18.0 ([#149](https://github.com/PostHog/posthog-flutter/pull/149))

## 4.9.2

- chore: improve error logging when capturing snapshots ([#146](https://github.com/PostHog/posthog-flutter/pull/146))

## 4.9.1

- fix: blank screen when viewing session replay recordings ([#139](https://github.com/PostHog/posthog-flutter/pull/139))

## 4.9.0

- feat: add getter for current session identifier ([#134](https://github.com/PostHog/posthog-flutter/pull/134))

## 4.8.0

- chore: change screenshots debouncing approach to throttling ([#131](https://github.com/PostHog/posthog-flutter/pull/131))
  - Added `throttleDelay` config and deprecated `debouncerDelay` config.

## 4.7.1

- chore: do not send repeated snapshots ([#126](https://github.com/PostHog/posthog-flutter/pull/126))

## 4.7.0

- chore: flutter session replay (Android and iOS) ([#123](https://github.com/PostHog/posthog-flutter/pull/123))
  - [Session replay docs](https://posthog.com/docs/session-replay/mobile), [PR pending review](https://github.com/PostHog/posthog.com/pull/10042)
  - Thanks @thisames for the [PR](https://github.com/PostHog/posthog-flutter/pull/116)!

## 4.6.0

- chore: change host to new address ([#106](https://github.com/PostHog/posthog-flutter/pull/106))
- chore: allow manual initialization of the SDK ([#117](https://github.com/PostHog/posthog-flutter/pull/117))

## 4.5.0

- add PrivacyInfo for macOS ([#105](https://github.com/PostHog/posthog-flutter/pull/105))

## 4.4.1

- fix: const `defaultHost` was renamed to `DEFAULT_HOST` and broke the Android build ([#98](https://github.com/PostHog/posthog-flutter/issues/98))

## 4.4.0

- chore: Allow overriding the route filtering using a ctor param `routeFilter` ([#95](https://github.com/PostHog/posthog-flutter/pull/95))

```dart
bool myRouteFilter(Route<dynamic>? route) =>
        route is PageRoute || route is OverlayRoute;
final observer = PosthogObserver(routeFilter: myRouteFilter);
```

## 4.3.0

- add PrivacyInfo ([#94](https://github.com/PostHog/posthog-flutter/pull/94))

## 4.2.0

- add flush method ([#92](https://github.com/PostHog/posthog-flutter/pull/92))

## 4.1.0

- add unregister method ([#86](https://github.com/PostHog/posthog-flutter/pull/86))

## 4.0.1

- Fix passing optional values to the JS SDK ([#84](https://github.com/PostHog/posthog-flutter/pull/84))

## 4.0.0

- Android minSdkVersion 21
- iOS min version 13.0
- Flutter min version 3.3.0
- Upgraded PostHog Android SDK to [v3](https://github.com/PostHog/posthog-android/blob/main/USAGE.md)
- Upgraded PostHog iOS SDK to [v3](https://github.com/PostHog/posthog-ios/blob/main/USAGE.md)
- Upgraded PostHog JS SDK to the latest version
- PostHog Flutter Plugins are written in Kotlin and Swift
- Added missing features such as feature flags payloads, debug, and more

## 4.0.0-RC.2

- Upgrade iOS SDK to [3.1.0](https://github.com/PostHog/posthog-ios/releases/tag/3.1.0) [#79](https://github.com/PostHog/posthog-flutter/pull/79)

## 4.0.0-RC.1

- Upgrade iOS SDK to [3.0.0](https://github.com/PostHog/posthog-ios/releases/tag/3.0.0) [#78](https://github.com/PostHog/posthog-flutter/pull/78)

## 4.0.0-beta.2

- Flutter macOS support [#76](https://github.com/PostHog/posthog-flutter/pull/76)

## 4.0.0-beta.1

- Record the root view as `root ('/')` instead of not recording at all [#74](https://github.com/PostHog/posthog-flutter/pull/74)
- Do not mutate the given properties when calling capture [#74](https://github.com/PostHog/posthog-flutter/pull/74)
  - Thanks @lukepighetti for the [PR](https://github.com/PostHog/posthog-flutter/pull/66)!
- Fix `CAPTURE_APPLICATION_LIFECYCLE_EVENTS` typo for iOS [#74](https://github.com/PostHog/posthog-flutter/pull/74)
- Added iOS support for the `DEBUG` config [#74](https://github.com/PostHog/posthog-flutter/pull/74)
- Upgrade iOS SDK that fixes missing `Application Opened` events [#74](https://github.com/PostHog/posthog-flutter/pull/74)

## 4.0.0-alpha.2

- Internal changes only

## 4.0.0-alpha.1

- Migrate to the new SDKs and latest tooling [#70](https://github.com/PostHog/posthog-flutter/pull/70)
  - Added missing features such as feature flags payloads, debug, and more

### Breaking changes

- Android minSdkVersion 21
- iOS min version 13.0
- Flutter min version 3.3.0
- Upgraded PostHog Android SDK to [v3](https://github.com/PostHog/posthog-android/blob/main/USAGE.md)
- Upgraded PostHog iOS SDK to [v3 preview](https://github.com/PostHog/posthog-ios/blob/main/USAGE.md)
- Upgraded PostHog JS SDK to the latest version
- PostHog Flutter Plugins are written in Kotlin and Swift

### Acknowledgements

Thanks @nehemiekoffi for the initial PR!

## 3.3.0

- Migrate to Java 8 and minSdkVersion 19 [#54](https://github.com/PostHog/posthog-flutter/pull/54)

## 3.2.0

- Add support to Dart v3.0.0 [#52](https://github.com/PostHog/posthog-flutter/pull/52)

## 3.1.0

- Adds support for `groups`
- Fixes a type issue with identify so that the userId is now always a String

## 3.0.5

- Fixes a bug with the iOS implementation for feature flags that stopped the SDK from building

## 3.0.4

- Adds CI/CD for deploying to pub.dev

## 3.0.0

- Adds basic feature flags support with `isFeatureEnabled` and `reloadFeatureFlags`

## 2.0.3

- Bugfixes with flutter web and identify call https://github.com/PostHog/posthog-flutter/pull/16

## 2.0.2

- Update to androidX for example android project
- Fix ios example app and params
- Fix web library, example, and docs

## 2.0.1

- Remove `generated_plugin_registrant.dart` from library

## 2.0.0

- Migrate to flutter 2

## 1.11.2

- Bump and pin version for Android lib to 1.1.1 because of bug

## 1.11.1

- Bump and pin version for Android lib to 1.1.0

## 1.11.0

- Bump the version for Android lib for screen \$screen_name consistency

## 1.10.0

- We will include the last screen that you set in the capture events now.
  This will require users to user `Posthog().capture()` instead of `Posthog.capture()`

## 1.9.3

- Bug fix for android identify method

## 1.9.2

- Rename entire repo from flutter-posthog to posthog-flutter

## 1.9.1

- Some renaming for consistency

## 1.9.0

- PostHog client library for Flutter is released!
