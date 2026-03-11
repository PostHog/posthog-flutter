## Contributing

If you wish to contribute a change to this repo, please send a [pull request](https://github.com/posthog/posthog-flutter/pulls).

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

- Run `make dryRelease` to build & publish the package to Maven local

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
