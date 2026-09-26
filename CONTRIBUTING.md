# Contributing

Thanks for your interest in improving the PostHog Flutter SDK.

## CI-aligned local checks

From the repository root, run the same checks CI uses:

```bash
flutter pub get
make installLinters
make checkFormatDart
make analyzeDart
make formatKotlin
make formatSwift
(cd posthog_flutter && flutter test)
(cd posthog_flutter && flutter test --platform chrome test/posthog_flutter_web_handler_test.dart test/posthog_flutter_web_setup_test.dart test/posthog_widget_web_test.dart test/posthog_widget_test.dart test/web_canvas_mask_provider_test.dart)
(cd posthog_flutter && flutter test --platform chrome --wasm test/posthog_isolate_error_handler_web_test.dart)
(cd sdk_compliance_adapter && flutter test test/feature_flag_has_experiment_test.dart test/flags_retry_test.dart test/minimal_flag_called_events_test.dart test/timestamp_test.dart)
```

The adapter's `test/adapter_server_test.dart` is the long-running compliance server,
not a finite unit test. Use the explicit list above rather than an unfiltered
`flutter test` in that package.

Use `flutter test --coverage` in `posthog_flutter` to generate `coverage/lcov.info`.
This measures Dart VM coverage, not browser or native code coverage.

## Build checks

CI also verifies the example app builds on the supported platforms. From the repository root:

```bash
flutter pub get
cd example
flutter build ios --simulator --no-codesign
flutter build macos
flutter build apk
flutter build web
```

If you want to exercise Swift Package Manager locally as well, run:

```bash
flutter config --enable-swift-package-manager
flutter pub get
cd example
flutter build ios --simulator --no-codesign
flutter build macos
```

## Testing with local native SDKs

The native SDK version floors in `posthog_flutter/darwin/posthog_flutter.podspec`,
`posthog_flutter/darwin/posthog_flutter/Package.swift`, and
`posthog_flutter/android/build.gradle` track the next expected native release. To
develop against an unreleased native branch, point the example app at your local
checkout with a gitignored override file — the committed build stays release-clean,
and a source override ignores the version floor.

### iOS

- Create `example/ios/Podfile.local` (gitignored) pointing at your checkout:

```ruby
pod 'PostHog', :path => File.expand_path('~/posthog-ios')
```

- Run `cd example/ios && pod install`, then `flutter run`.

The example `Podfile` evaluates `Podfile.local` when present, so no committed file
changes.

### Android

- Create `example/android/local.settings.gradle.kts` (gitignored) with a composite
  build of your checkout:

```kotlin
// absolute path — Kotlin does not expand "~"
includeBuild("/absolute/path/to/posthog-android")
```

- Run `flutter run`.

Gradle substitutes `com.posthog:posthog(-android)` with the local source regardless
of the version floor, so no publishing or `mavenLocal()` is needed. As a fallback you
can still `make dryRelease` in `posthog-android` (add `-PandroidVersion=<floor>` so the
published version satisfies the floor) and add `mavenLocal()` to the repositories.

## Public API changes

Public API is hard to change once it ships, so agree on it before writing the implementation. Our [SDK guidelines](https://posthog.com/handbook/engineering/sdks/guidelines) explain how we design it.

This section is for external contributors. PostHog maintainers (members of the PostHog GitHub org) agree on API shape in the PR itself, so they don't need a separate issue.

- **Before you start:** if you need something the SDK doesn't support and it would add or change a public option, method, or type, open an issue describing your use case. Wait for a maintainer to agree on the API shape there before you implement it. Context is more useful to us than code at this stage.
- **Already specified?** If a published [sdk-spec](https://github.com/PostHog/sdk-specs) defines the API, that's the agreement, so you don't need an issue.
- **Already have a PR open?** Don't stop or rewrite it. Call out the public API change at the top of the PR description, and link or open an issue so we can discuss the shape there.
- Check first whether an existing option or hook, such as `beforeSend`, already covers the use case. We avoid offering two ways to do the same thing.
- If a reviewer suggests a different API on your PR, confirm it with them before re-implementing. Treat it as a question, not an instruction.

`make updateApiDart` regenerates `api/posthog_flutter.api.json`, and CI runs `make checkApiDart` to catch an outdated snapshot. A diff in that file means your change touches public API.
