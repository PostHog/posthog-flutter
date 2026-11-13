# Getting started

The Flutter SDK runs in iOS, Android, macOS, and web apps.

To send your first event, add `posthog_flutter`, then call `setup` once before `runApp` with your project token and host from your [project settings](https://app.posthog.com/project/settings).

Use `capture` for your own events, and call `flush` and `close` before the app exits.

Install the package:

```bash
flutter pub add posthog_flutter
```

Initialize the SDK once, before `runApp`, with your project token and host:

```dart
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = PostHogConfig('<ph_project_token>');
  config.host = 'https://us.i.posthog.com';
  await Posthog().setup(config);

  runApp(const MyApp());
}
```

Capture an event and identify the user:

```dart
await Posthog().capture(eventName: 'user_signed_up', properties: {'plan': 'free'});
await Posthog().identify(userId: 'user_123', userProperties: {'email': 'a@example.com'});
```

Flush queued events and shut the SDK down before the app exits:

```dart
await Posthog().flush();
await Posthog().close();
```

## Reproducible Android builds and Shorebird

`posthog_flutter` allows a range of versions of the native PostHog Android SDK, which depends on the PostHog core library. Gradle can pick a newer native version even when your `posthog_flutter` version stays the same, and `pubspec.lock` doesn't lock Gradle dependencies.

[Shorebird](https://docs.shorebird.dev/code-push/troubleshooting/) patches can't update native Android code. Pin both native libraries before you create a release, so the release and its patches use the same versions.

From your app's `android` directory, list the versions your release build selects:

```bash
./gradlew :app:dependencyInsight --dependency com.posthog --configuration releaseRuntimeClasspath
```

With product flavors, use your release variant's configuration, such as `productionReleaseRuntimeClasspath`. Note the versions of `com.posthog:posthog-android` and `com.posthog:posthog`. Their version numbers differ.

Add those versions as strict constraints in `android/app/build.gradle.kts`:

```kotlin
dependencies {
    constraints {
        implementation("com.posthog:posthog-android") {
            version { strictly("<android-sdk-version>") }
        }
        implementation("com.posthog:posthog") {
            version { strictly("<core-version>") }
        }
    }
}
```

In a Groovy `build.gradle`, write `version { strictly "<version>" }` inside each constraint. Gradle can still upgrade a plain version declaration, and a [strict constraint](https://docs.gradle.org/current/userguide/dependency_versions.html#sec:rich-version-constraints) stops that.

Run the dependency report again, build your app, and check that events arrive in PostHog. Commit the constraints and `pubspec.lock`.

- For an existing Shorebird release, use the native versions recorded for that release, not the versions a new build resolves.
- The pins cover PostHog only. To pin other plugins and build tools, use [Gradle dependency locking](https://docs.gradle.org/current/userguide/dependency_locking.html).
- Pins also block automatic native bug fixes. When you upgrade PostHog, choose compatible native versions together and test event capture before a new app store release.
- Don't upgrade native dependencies in a Dart-only patch, and don't force a version below the minimum that `posthog_flutter` requires.
