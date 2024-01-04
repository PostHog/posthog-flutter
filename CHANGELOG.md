## Next

- Migrate to the new SDKs and latest tooling [#70](https://github.com/PostHog/posthog-flutter/pull/70)
  - Added missing features such as feature flags payloads, debug, and more

### Breaking changes

- Android minSdkVersion 21
- iOS min version 13.0
- Flutter min version 3.3.0
- Upgraded PostHog Android SDK to [v3](https://github.com/PostHog/posthog-android/blob/main/USAGE.md)
- Upgraded PostHog iOS SDK to [v3 preview](https://github.com/PostHog/posthog-ios/blob/main/USAGE.md)
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
