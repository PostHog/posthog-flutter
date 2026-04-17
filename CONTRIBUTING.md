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

### iOS

- Update `example/ios/Podfile` to override the `PostHog` pod with your local path:

```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # add this
  pod 'PostHog', :path => File.expand_path('~/posthog-ios')
end
```

- Run `cd example/ios && pod install` to install the local pod
- Open iOS simulator
- Run the app with `flutter run`

### Android

In your local `posthog-android` repo:

- Run `make dryRelease` to build and publish the package to Maven local

In the `posthog-flutter` repo:

- Update `/android/build.gradle` to add `mavenLocal()` as a repository:

```gradle
allprojects {
    repositories {
        mavenLocal() // add this
        google()
        mavenCentral()
    }
}
```

- Open Android simulator
- Run the app with `flutter run`
