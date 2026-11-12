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

## Install with the wizard

Run this command in your project directory to add PostHog to your Flutter project. The wizard detects your framework, installs the SDK, and sets up your first events:

```bash
npx -y @posthog/wizard@latest
```

Or set it up manually with the rest of this guide.

## Check the requirements

| Requirement | Minimum |
| --- | --- |
| Flutter SDK | 3.41.0 |
| Xcode | 26 |
| iOS deployment target | 15.0 |
| macOS deployment target | 11.0 |
| Android `minSdkVersion` | 23 |

On iOS and macOS, the SDK installs only through [Swift Package Manager](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers). It has no podspec, so it doesn't install through CocoaPods.

Flutter 3.44.0 and later turn Swift Package Manager on by default. On earlier versions, or if you turned it off, run:

```bash
flutter config --enable-swift-package-manager
```

Then rebuild your app. Plugins that only support CocoaPods keep working through your `Podfile`.

## Set up platforms

`posthog_flutter` is on [Pub](https://pub.dev/packages/posthog_flutter). Instead of `flutter pub add`, you can add it to your `pubspec.yaml` yourself:

```yaml
# rest of your code

dependencies:
  flutter:
    sdk: flutter
  posthog_flutter: ^6.0.0

# rest of your code
```

On Android and iOS, you can start the SDK in two ways:

- **Automatically.** You put your project token and host in the native config files. The native SDK starts on its own, and you need no Dart setup.
- **Manually.** You turn off `com.posthog.posthog.AUTO_INIT` and call `Posthog().setup(config)` in Dart. This gives you more control and more settings.

> **Note.** For session replay and surveys, you must set up the SDK manually with `com.posthog.posthog.AUTO_INIT` turned off.

With automatic setup, the application lifecycle events have no special context set when the SDK starts.

### Android setup

To start the SDK automatically, add your PostHog settings to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="your.package.name">
    <application>
        <!-- ... other configuration ... -->
        <meta-data android:name="com.posthog.posthog.PROJECT_TOKEN" android:value="<ph_project_token>" />
        <meta-data android:name="com.posthog.posthog.POSTHOG_HOST" android:value="<ph_client_api_host>" />  <!-- usually 'https://us.i.posthog.com' or 'https://eu.i.posthog.com' -->
        <!-- com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS is enabled by default since version 5.23.0 (previously named TRACK_APPLICATION_LIFECYCLE_EVENTS, which still works as an alias) -->
        <meta-data android:name="com.posthog.posthog.DEBUG" android:value="true" />
    </application>
</manifest>
```

To start it manually, turn off `AUTO_INIT` in the same file:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="your.package.name">
    <application>
        <!-- ... other configuration ... -->
        <meta-data android:name="com.posthog.posthog.AUTO_INIT" android:value="false" />
    </application>
</manifest>
```

In both cases, set the minimum Android SDK version to `23` in `android/app/build.gradle`:

```groovy
// rest of your config

    defaultConfig {
        minSdkVersion 23
        // rest of your config
    }

// rest of your config
```

### iOS setup

To start the SDK automatically, add your PostHog settings to `ios/Runner/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- rest of your configuration -->
	<key>com.posthog.posthog.PROJECT_TOKEN</key>
	<string><ph_project_token></string>
	<key>com.posthog.posthog.POSTHOG_HOST</key>
	<string><ph_client_api_host></string>
	<!-- com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS is enabled by default since version 5.23.0 -->
	<key>com.posthog.posthog.DEBUG</key>
	<true/>
</dict>
</plist>
```

To start it manually, turn off `AUTO_INIT` in the same file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- rest of your configuration -->
	<key>com.posthog.posthog.AUTO_INIT</key>
	<false/>
</dict>
</plist>
```

In both cases, set the minimum platform version to iOS 15.0. In Xcode, set **Minimum Deployments** for the `Runner` target (**Runner > General > Minimum Deployments**). Then regenerate the iOS project's configuration files:

```bash
flutter build ios --config-only
```

If you keep a `Podfile` for other plugins, raise its platform in `ios/Podfile` too:

```ruby
platform :ios, '15.0'
# rest of your config
```

### Dart setup

If you chose automatic setup, you need no more configuration in Dart.

If you chose manual setup, call `setup` before `runApp`:

```dart
import 'package:flutter/material.dart';

import 'package:posthog_flutter/posthog_flutter.dart';

Future<void> main() async {
  // init WidgetsFlutterBinding if not yet
  WidgetsFlutterBinding.ensureInitialized();
  final config = PostHogConfig('<ph_project_token>');
  config.debug = true;
  // captureApplicationLifecycleEvents is enabled by default since version 5.23.0
  config.host = '<ph_client_api_host>';
  await Posthog().setup(config);
  runApp(MyApp());
}
```

### Web setup

If your project has a `web/` directory, this step is required. `Posthog().setup()` does nothing on web, so a web build without the snippet below captures nothing.

Add your web snippet, which you can find in [your project settings](https://us.posthog.com/settings/project#snippet), to the `<head>` of your `web/index.html` file. Write your project token into the snippet as a literal string. The token is public and ships to every visitor, so it needs no build-time or deploy-time injection:

```html
<!DOCTYPE html>
<html>
  <head>
    <!-- ... other head elements ... -->

    <script async>
      !(function (t, e) {
        var o, n, p, r;
        e.__SV ||
          ((window.posthog = e),
          (e._i = []),
          (e.init = function (i, s, a) {
            function g(t, e) {
              var o = e.split(".");
              (2 == o.length && ((t = t[o[0]]), (e = o[1])),
                (t[e] = function () {
                  t.push([e].concat(Array.prototype.slice.call(arguments, 0)));
                }));
            }
            (((p = t.createElement("script")).type = "text/javascript"),
              (p.crossOrigin = "anonymous"),
              (p.async = !0),
              (p.src = s.api_host + "/static/array.js"),
              (r = t.getElementsByTagName("script")[0]).parentNode.insertBefore(p, r));
            var u = e;
            for (
              void 0 !== a ? (u = e[a] = []) : (a = "posthog"),
                u.people = u.people || [],
                Object.defineProperty(u, "toString", {
                  configurable: !0,
                  enumerable: !0,
                  writable: !0,
                  value: function (t) {
                    var e = "posthog";
                    return ("posthog" !== a && (e += "." + a), t || (e += " (stub)"), e);
                  },
                }),
                Object.defineProperty(u.people, "toString", {
                  configurable: !0,
                  enumerable: !0,
                  writable: !0,
                  value: function () {
                    return u.toString(1) + ".people (stub)";
                  },
                }),
                o =
                  "capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagResult reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys getNextSurveyStep onSessionId".split(
                    " ",
                  ),
                n = 0;
              n < o.length;
              n++
            )
              g(u, o[n]);
            e._i.push([i, s, a]);
          }),
          (e.__SV = 1));
      })(document, window.posthog || []);
      posthog.init("<ph_project_token>", {
        api_host: "<ph_client_api_host>", // 'https://us.i.posthog.com' or 'https://eu.i.posthog.com'
        defaults: "<ph_posthog_js_defaults>",
      });
    </script>
  </head>

  <!-- other elements -->
</html>
```

For more on the web snippet, see the [JavaScript Web SDK docs](https://posthog.com/docs/libraries/js/reference).

## Pin Android dependencies

The Flutter SDK uses the native PostHog Android SDK, which depends on the PostHog core library. The Flutter package permits a range of Android SDK versions, so Gradle can select a newer native version even when your `posthog_flutter` version hasn't changed. Your `pubspec.lock` doesn't lock these Gradle dependencies.

This matters for reproducible Android builds and for [Shorebird](https://docs.shorebird.dev/code-push/troubleshooting/) patches, which can't update native Android code. To keep PostHog's native dependencies the same between a release and its patches, pin both native libraries before you create the release:

1. Inspect the versions selected for your release build. From your app's `android` directory, run:

   ```bash
   ./gradlew :app:dependencyInsight --dependency com.posthog --configuration releaseRuntimeClasspath
   ```

   If you use product flavors, replace `releaseRuntimeClasspath` with your release variant's configuration, such as `productionReleaseRuntimeClasspath`. Record the selected versions of `com.posthog:posthog-android` and `com.posthog:posthog`. Their version numbers differ.

2. Add strict constraints to your app's `android/app/build.gradle.kts`. Replace the placeholders with the versions selected together in the previous step:

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

   For a Groovy `build.gradle`, use the same dependency declarations with `version { strictly "<version>" }` inside each constraint. A plain version declaration can still be upgraded during Gradle conflict resolution. [Strict constraints](https://docs.gradle.org/current/userguide/dependency_versions.html#sec:rich-version-constraints) enforce the selected versions.

3. Run the dependency report again, build your app, and verify that events arrive in PostHog. Commit the constraints and `pubspec.lock`, and use the same versions for the release and its patches.

For an existing Shorebird release, use the native versions recorded for that release, not versions resolved by a fresh build today. Pinning PostHog alone doesn't freeze other plugins or your build tools. For broader dependency control, see [Gradle dependency locking](https://docs.gradle.org/current/userguide/dependency_locking.html).

Pins also prevent automatic native bug fixes. When you upgrade PostHog, review the pins, select compatible native versions together, and test event capture before you ship a new app store release. Don't upgrade native dependencies in a Dart-only patch, and don't force an old version below the Flutter package's required minimum.

## Autocapture events

The SDK captures these events for you:

- **`Application Opened`.** The app opens from a closed state or comes to the foreground, for example from the app switcher.
- **`Application Backgrounded`.** The user sends the app to the background.
- **`Application Installed`.** The app is installed.
- **`Application Updated`.** The app is updated.
- **`$screen`.** The user navigates, once you add the `PosthogObserver`. See [Capture screen views](#capture-screen-views).
- **`$exception`.** The app throws an exception.
- **`$autocapture`.** The user interacts with elements on Flutter web, captured by posthog-js.
- **`$rageclick`.** The user rapidly taps in the same area. This works on iOS and macCatalyst by default, and on Flutter web through posthog-js. See [Capture rage clicks](#capture-rage-clicks).

The Flutter SDK doesn't autocapture taps or other widget interactions on iOS or Android.

On Flutter web, interaction autocapture and rage clicks come from [posthog-js](https://posthog.com/docs/libraries/js/reference). You configure them in the `posthog.init` call in your `web/index.html`. The Flutter SDK doesn't call `posthog.init` itself, so these options don't go in `PostHogConfig`.

## Capture screen views

Screen views aren't captured automatically. Add the `PosthogObserver` to your app yourself. Without it, your app sends no `$screen` events at all.

This works with any routing package, not just the plain `Navigator` API. Add the observer wherever your router takes navigator observers, as shown below for `MaterialApp` and `go_router`.

> **Note.** Screen names come from each route's `RouteSettings.name`. Most routing packages set this for you. If yours doesn't, name your routes so `$screen` events are readable.

### Use navigatorObservers

Add the `PosthogObserver` to record screen views automatically:

```dart
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // If you're using session replay, `PostHogWidget` has to be the root, and `MaterialApp` must be the child.
    return MaterialApp(
      navigatorObservers: [
        // The PosthogObserver records screen views automatically
        PosthogObserver(),
      ],
      ...
    );
  }
}
```

Name your routes:

```dart
...
MaterialPageRoute(builder: (context) => const HomeScreenRoute(),
  settings: const RouteSettings(name: 'Home Screen'),
),
...
```

### Use go_router

Add the `PosthogObserver` to record screen views automatically:

```dart
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:go_router/go_router.dart';

// GoRouter configuration
final _router = GoRouter(
  routes: [
    ...
  ],
  // The PosthogObserver records screen views automatically
  observers: [PosthogObserver()],
);

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // If you're using session replay, `PostHogWidget` has to be the root, and `MaterialApp` must be the child.
    return MaterialApp.router(
      routerConfig: _router,
    );
  }
}
```

Name your routes:

```dart
...
GoRoute(
  name: 'Home Screen',
  ...
),
...
```

## Capture rage clicks

> **Note.** On iOS and macCatalyst, the native SDK captures `$rageclick` by default through `PostHogConfig.rageClickConfig`. These events don't name the widget. Android doesn't support rage clicks. See `PostHogRageClickConfig` in the reference for the thresholds.

On Flutter web, a `$rageclick` event names the widget a user tapped, but only after you enable autocapture in posthog-js and semantics in Flutter. Without both, you either get no rage clicks or rage clicks that only report `flutter-view`.

1. **Enable autocapture and rage clicks in `web/index.html`.** posthog-js detects rage clicks inside its autocapture click handler, so `$rageclick` doesn't fire while `autocapture` is off.

   ```js
   posthog.init('<ph_project_token>', {
     api_host: '<ph_client_api_host>',
     autocapture: true,
     rageclick: true,
   })
   ```

   If you want to limit autocapture to tappable widgets, use `css_selector_allowlist: ['[role="button"]']`. Don't use `element_allowlist: ['button']`. Flutter's semantics nodes are `flt-semantics` elements, not `<button>` elements, so that allowlist matches nothing. Rage clicks go through the same allowlist check as `$autocapture`, so an allowlist that matches no semantics node drops rage clicks too.

2. **Enable semantics in `main.dart`.** Flutter web draws your app into a single canvas, so by default every click targets the `flutter-view` element and `$rageclick` has no `$el_text`. With semantics on, Flutter places a `flt-semantics` node over each widget and tappable nodes receive the click. `$rageclick` then includes the widget label and `role` in `$elements_chain`. Which field carries the label depends on how Flutter renders the semantics node. A leaf button puts the label in DOM text, which fills `$el_text`. A node with children puts it in `aria-label`.

   ```dart
   import 'package:flutter/semantics.dart';

   void main() {
     WidgetsFlutterBinding.ensureInitialized();
     SemanticsBinding.instance.ensureSemantics();
     runApp(const MyApp());
   }
   ```

   Semantics also changes how Flutter web delivers taps. On a tappable widget, the engine sends a semantic tap action instead of raw pointer events. `onPressed` and `onTap` keep working, but code that relies on `Listener`, `onTapDown`/`onTapUp`, custom gesture recognizers, or drags that start on a button needs testing. Flutter already turns semantics on when a screen reader is active, so assistive-technology users get this behavior today. A custom Dart rage click detector built on raw pointer events can't coexist with semantics on the same widgets, so choose one approach.

3. **Optional: give key widgets a stable identifier.** Wrap a widget in `Semantics(identifier: 'cashier_deposit', child: ...)` and the identifier appears in `$elements_chain` as `attr__flt-semantics-identifier`. Flutter puts the identifier on a parent `group` node rather than on the button node itself, so filter with **Elements chain contains** `cashier_deposit` instead of matching the clicked element.

Semantics adds per-frame work on web. If a screen has many widgets, profile it before and after you turn semantics on.

These steps work with Flutter 3.44.8 and posthog-js 1.438.0.

## Identify users

Call `identify` as soon as you can, typically right after your user logs in. This links the events from their sessions to them across devices and platforms. When you call `identify`, all previously tracked anonymous events are linked to the user.

For `userProperties` and `userPropertiesSetOnce`, see [person properties](https://posthog.com/docs/product-analytics/person-properties) and [the difference between set and set once](https://posthog.com/docs/product-analytics/person-properties#what-is-the-difference-between-set-and-set_once). Read [Identifying users](https://posthog.com/docs/product-analytics/identify) to use this method correctly.

### Get the distinct ID

To get the current user's distinct ID, call `Posthog().getDistinctId()`. It returns either the ID PostHog generated or the ID you passed to `identify()`. You can use it to check whether you've already called `identify` for a user.

### Alias a user

Sometimes you want to assign multiple distinct IDs to a single user. This helps when your primary distinct ID is inaccessible. For example, a distinct ID you use on the frontend isn't available in your backend.

In this case, use `alias` to assign another distinct ID to the same user:

```dart
await Posthog().alias(
  alias: 'distinct_id',
);
```

Read the docs on [alias](https://posthog.com/docs/product-analytics/identify#alias-assigning-multiple-distinct-ids-to-the-same-user) to use this method correctly.

## Set person profiles

PostHog captures two types of events: [anonymous and identified](https://posthog.com/docs/data/anonymous-vs-identified-events).

**Identified events** let you attribute events to specific users and attach [person properties](https://posthog.com/docs/product-analytics/person-properties). They're best suited for logged-in users. Capture identified events when you:

- Track logged-in users in B2B and B2C SaaS apps
- Do user-segmented product analysis
- Analyze the complete conversion lifecycle for growth and marketing

**Anonymous events** are events without individually identifiable data. They're best suited for [web analytics](https://posthog.com/docs/web-analytics) or apps where users aren't logged in. Capture anonymous events when you:

- Track a marketing website
- Run a content-focused site
- Have a B2C app where users don't sign up or log in

For identified events, PostHog creates a [person profile](https://posthog.com/docs/data/persons) for the user. For anonymous events, it doesn't.

> **Important.** Anonymous events cost less to process, so they can be up to 4x cheaper than identified ones. Only capture identified events when you need them.

### Capture anonymous events

The Flutter SDK captures anonymous events by default. This depends on the `personProfiles` setting you pass when you initialize PostHog:

- **`PostHogPersonProfiles.identifiedOnly`.** The default, and recommended. Events are anonymous until a person profile exists for the user. After that, they're identified.
- **`PostHogPersonProfiles.always`.** Every event is identified.
- **`PostHogPersonProfiles.never`.** Every event is anonymous.

For example:

```dart
final config = PostHogConfig('<ph_project_token>');
config.host = '<ph_client_api_host>';
config.personProfiles = PostHogPersonProfiles.identifiedOnly;
```

### Capture identified events

With `PostHogPersonProfiles.identifiedOnly`, call any of these to start capturing identified events:

- [`identify()`](https://posthog.com/docs/product-analytics/identify)
- [`alias()`](https://posthog.com/docs/product-analytics/identify#alias-assigning-multiple-distinct-ids-to-the-same-user)
- [`group()`](https://posthog.com/docs/product-analytics/group-analytics)

Each of these creates a person profile for the user. Once the profile exists, all later events for this user are captured as identified events.

You can also set `personProfiles` to `PostHogPersonProfiles.always` to capture identified events by default.

## Set super properties

Super properties are properties you set once and that are then sent with every event, whether it's a `$screen` or anything else.

Set them with `Posthog().register`, which takes a key and a value. They persist across sessions:

```dart
import 'package:posthog_flutter/posthog_flutter.dart';

await Posthog().register("team_id", 22);
```

After this call, every event from the user includes `"team_id": 22`. If you filter events by `team_id = 22`, you get all events captured for that user after the `register` call.

Super properties aren't stored on the person, only on their events. To store properties on the person, use `Posthog().identify`. See [Identify users](#identify-users).

Because super properties persist across sessions, you have to remove them when they no longer apply. To stop sending one, call `Posthog().unregister`:

```dart
import 'package:posthog_flutter/posthog_flutter.dart';

await Posthog().unregister("team_id");
```

Later events don't include it.

If you do this when a user logs out, call `Posthog().reset()` instead. It clears all stored super properties and more.

## Use group analytics

Group analytics lets you associate the events in a person's session with a group, such as a team or an organization. See [Group analytics](https://posthog.com/docs/product-analytics/group-analytics) for Flutter examples and implementation details.

> **Note.** Group analytics is a paid feature. See the [pricing page](https://posthog.com/pricing).

## Use feature flags

PostHog's [feature flags](https://posthog.com/docs/feature-flags) let you safely deploy and roll back new features, and target specific users and groups with them.

### Boolean feature flags

```dart
final result = await Posthog().getFeatureFlagResult('flag-key');
if (result != null && result.enabled) {
  // Do something differently for this user

  // Optional: fetch the payload from the same evaluation result
  final matchedFlagPayload = result.payload;
}
```

### Multivariate feature flags

```dart
final result = await Posthog().getFeatureFlagResult('flag-key');
if (result != null && result.variant == 'variant-key') { // replace 'variant-key' with the key of your variant
  // Do something differently for this user

  // Optional: fetch the payload from the same evaluation result
  final matchedFlagPayload = result.payload;
}
```

### Wait for flags to load

Every time a user opens the app, the SDK sends a request in the background to fetch the feature flags that apply to that user. It stores those flags on the device.

For most screens, this means the flags are available immediately, except the first time a user opens the app.

To handle this, register a callback with `Posthog().onFeatureFlags()` before `setup()`. It runs after every feature flags load:

```dart
final config = PostHogConfig('<ph_project_token>');
config.host = '<ph_client_api_host>';
Posthog().onFeatureFlags((loaded) async {
  if (await Posthog().isFeatureEnabled('flag-key')) {
    // do something
  }
});
await Posthog().setup(config);
```

### Reload feature flags

Feature flag values are cached. If something changed for your user and you want to fetch their flag values again, call:

```dart
await Posthog().reloadFeatureFlags();
```

### Bootstrap flags

There's a delay between initializing PostHog and fetching feature flags, so flags aren't always available immediately. This makes them unusable for something like routing a user to a different screen based on a flag.

To have your flags available immediately, initialize PostHog with precomputed values to use until it fetches them. This is called bootstrapping. After the SDK fetches flags from PostHog, it uses those values instead of the bootstrapped ones.

Set `config.bootstrap` before you call `setup()` to seed identity and flag values before the first `/flags` response:

```dart
final config = PostHogConfig('<ph_project_token>');
config.host = '<ph_client_api_host>';
config.bootstrap = PostHogBootstrapConfig(
  distinctId: 'distinct_id_of_your_user',
  isIdentifiedId: true,
  featureFlags: {
    'flag-1': true,
    'variant-flag': 'control',
  },
);
await Posthog().setup(config);
```

The values are forwarded to the native iOS and Android SDKs:

- **Bootstrapped identity applies during setup.** On a fresh install, events captured during initialization, like `Application Installed`, carry your distinct ID instead of the SDK-generated UUID.
- **An anonymous bootstrap.** With `isIdentifiedId: false`, the default, the SDK seeds the anonymous ID only when none is stored yet. Once an anonymous ID exists on disk, or the person has been identified, the SDK ignores it.
- **An identified bootstrap on a fresh install.** With `isIdentifiedId: true`, you pass a signed-in identity your app already has, for example from a backend session token. The SDK seeds the distinct ID, marks the person identified, and generates a separate device ID.
- **An identified bootstrap on a returning install.** A matching anonymous ID is marked identified without an `$identify` event. A different anonymous ID is merged with `identify()` when person profiles are enabled, which emits `$identify` unless capturing is opted out. A different, already identified person is left untouched.
- **Bootstrapped flags are served until the first `/flags` response.** A complete `/flags` response takes over entirely, so keys that were only bootstrapped don't persist past it. `reset()` clears bootstrapped flags.
- **Only enabled flags are seeded.** That's a `true` boolean or a non-empty variant string. A `false` or empty value is dropped, as in posthog-js.
- **Payloads have their own option.** Seed them with `featureFlagPayloads`. Flag values and payloads must be JSON-serializable, or they're dropped.

The feature flags loaded callback fires as soon as bootstrapped flags are applied, so startup logic can read them immediately. The SDK doesn't support the `sessionID` bootstrap option. When `personProfiles` is `PostHogPersonProfiles.never`, the SDK keeps a different anonymous identity instead of merging it into an identified bootstrap.

On Flutter web, `bootstrap` isn't applied, so configure it in your `posthog.init({...})` snippet instead. See the [SDK bootstrapping guide](https://posthog.com/docs/libraries/bootstrapping) for the cross-SDK overview.

### Set properties for flags

If a flag targets person or group properties, you can send those properties with the next flag evaluation request instead of waiting for a `$set` event to be ingested. This avoids a stale flag value right after you set a property.

Use `setPersonPropertiesForFlags()` and `setGroupPropertiesForFlags()` to set them. Pass `reloadFeatureFlags: false` to set several properties before reloading. Use `resetPersonPropertiesForFlags()` and `resetGroupPropertiesForFlags()` to clear them. See [property overrides for flag evaluation](https://posthog.com/docs/feature-flags/property-overrides) for details.

### Run experiments

[Experiments](https://posthog.com/docs/experiments/start-here) use feature flags, so the code for running an experiment is very similar to the feature flags code. See the [feature flag code examples](https://posthog.com/docs/feature-flags/adding-feature-flag-code?tab=Flutter) for Flutter.

You can also [run experiments without feature flags](https://posthog.com/docs/experiments/running-experiments-without-feature-flags).

## Track errors

To set up error tracking in your project, see the [error tracking docs](https://posthog.com/docs/error-tracking).

## Send logs

To set up [logs](https://posthog.com/docs/logs) in your Flutter app, follow the [Flutter logs installation guide](https://posthog.com/docs/logs/installation/flutter).

The SDK exposes `Posthog().logger.{trace,debug,info,warn,error,fatal}`, and `Posthog().captureLog` for full control. They send structured records to PostHog Logs, with batching, offline persistence, and a rate cap built in.

## Record session replays

> **Note.** Session replay is supported on Flutter web, Android, and iOS.

To set up [web session replay](https://posthog.com/docs/session-replay) or [mobile session replay](https://posthog.com/docs/session-replay/mobile):

1. Install the Flutter SDK.
2. Follow the [additional installation instructions](https://posthog.com/docs/session-replay/installation/flutter).
3. Enable **Record user sessions** in [your project settings](https://us.posthog.com/settings/project-replay).
4. Enable the `sessionReplay` option in your config.

If you're using Flutter web, also enable [canvas capture](https://posthog.com/docs/session-replay/canvas-recording) in [your project settings](https://us.posthog.com/settings/project-replay). Flutter renders your app in a browser canvas element, so replay needs it.

On Flutter web, masking with `maskAllTexts`, `maskAllImages`, and `PostHogMaskWidget` applies inside that canvas too. To enable it, declare `session_recording.canvasCapture.maskRegionsFn` in the `posthog.init` call in your `web/index.html`. This requires posthog-js 1.408.0 or later. See the Flutter tab of the [session replay privacy docs](https://posthog.com/docs/session-replay/privacy).

## Show surveys

> **Note.** Surveys are supported in Flutter on web, iOS, and Android.

[Surveys](https://posthog.com/docs/surveys) launched with [popover presentation](https://posthog.com/docs/surveys/creating-surveys#presentation) are shown automatically to users who match the [display conditions](https://posthog.com/docs/surveys/creating-surveys#display-conditions) you set up.

## Send push notifications

The Flutter SDK can register a device for [Workflows](https://posthog.com/docs/workflows) push notifications and capture when a user opens one. For setup, see [Push notifications](https://posthog.com/docs/workflows/push-notifications). It covers automatic and manual registration, capturing opens, opting out, and identity verification.

## Send AI events

To send [AI observability](https://posthog.com/docs/ai-observability) events you build yourself, such as `$ai_generation`, `$ai_span`, or `$ai_embedding`, call `captureAi` instead of `capture`. It works on iOS, macOS, Android, Windows, and Linux. It sends the event to PostHog's [AI endpoint](https://posthog.com/docs/ai-observability/large-events), which accepts much larger events than `capture`.

```dart
final uuid = await Posthog().captureAi(
  eventName: r'$ai_generation',
  properties: {
    r'$ai_trace_id': traceId,
    r'$ai_model': 'gpt-5',
    r'$ai_provider': 'openai',
    r'$ai_input_tokens': 120,
    r'$ai_output_tokens': 45,
  },
);
```

`captureAi` returns the event's UUID once the event is queued, and `null` when it isn't. An empty event name also returns `null`.

- **Separate queue.** AI events have their own on-disk queue, so large events don't push your other events out. `flush()` and `close()` send both queues.
- **`capture` doesn't reroute AI events.** `capture` never sends `$ai_` events to the AI endpoint, so use `captureAi` for them. The SDK logs a debug message when you pass `captureAi` a name that doesn't start with `$ai_`.

For the other `null` cases, the size limits, and the `captureAiCompression`, `captureAiMaxQueueSize`, `captureAiTimeout`, and `captureAiMaxEventBytes` settings, see [`Posthog.captureAi`](https://posthog.com/docs/libraries/flutter/reference#capture-ai) and `PostHogConfig` in the reference. Leave a setting `null` to keep the SDK default.

## Flush events

The SDK puts events in an internal queue, so calls are fast and don't block. It sends them in batches in the background.

You can set how many events queue before a flush with `flushAt`. The default is `20`. Setting it to `1` sends events immediately and uses more battery.

You can also set `flushInterval`, which defaults to 30 seconds. After it passes, queued events are sent regardless of how many have been gathered:

```dart
final config = PostHogConfig('<ph_project_token>');
config.flushAt = 20;
config.flushInterval = const Duration(seconds: 30);
```

You can also flush the queue manually to start sending events immediately instead of waiting for the next batch:

```dart
await Posthog().flush();
```

Flushing is best-effort and asynchronous. It starts sending queued events in the background but doesn't wait for the request to finish, so it isn't a delivery guarantee.

## Queue events offline

On Android and Apple platforms, the SDK keeps capturing events while the device is offline. It stores them in a queue in the device's file storage and flushes them when the device is back online.

- **Maximum size.** The queue holds up to `maxQueueSize` events.
- **Full queue.** When the queue is full, the oldest event is deleted first.
- **Restart.** The queue is flushed when the app restarts and the device is online.

## Opt out of capture

You can turn off data collection for a user at any time with `optOut()`:

```dart
await Posthog().optOut();
```

This stops any future events from being sent. It doesn't remove events already captured for the user.

To opt the user back in:

```dart
await Posthog().optIn();
```

To check if a user is opted out:

```dart
await Posthog().isOptOut();
```

## Filter screen events

`beforeSend` callbacks let you amend or drop events before they're sent to PostHog. For redacting and dropping events, and for which events the callbacks see, see `PostHogConfig.beforeSend` in the reference.

You can also use them to stop specific screens from being autocaptured. Return `null` for any `$screen` event whose `$screen_name` matches a screen you don't want to track. The event is dropped before it's sent, which keeps unwanted screen views out of your event log.

Because it's just a function, you can filter however you like:

- **An ignorelist.** Drop the screens you name.
- **An allowlist.** Invert the check to capture only the screens you name.
- **A custom rule.** Use a name prefix, a regex, or a check against the event's properties.

```dart
const ignoredScreens = {'Splash', 'Debug'};

config.beforeSend = [
  (event) {
    final screenName = event.properties?['$screen_name'];
    if (event.event == '$screen' && ignoredScreens.contains(screenName)) {
      return null;
    }
    return event;
  },
];
```

## Enable debug mode

If you're not seeing the events, feature flags, or surveys you expect, turn on debug mode to see what's happening.

Set `debug` to `true` in your `PostHogConfig` when you initialize the SDK. A common pattern is to turn it on only in development environments with an environment variable:

```dart
final config = PostHogConfig('<ph_project_token>');
config.host = '<ph_client_api_host>';
config.debug = true;
await Posthog().setup(config);
```

This turns on verbose logs about the inner workings of the SDK.

You can also turn debug mode on and off with `Posthog().debug()`:

```dart
await Posthog().debug(true);
await Posthog().debug(false);
```
