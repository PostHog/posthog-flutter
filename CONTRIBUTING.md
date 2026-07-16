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
cd posthog_flutter && flutter test
```

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
