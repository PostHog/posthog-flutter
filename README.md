# PostHog plugin

[![Package on pub.dev][pubdev_badge]][pubdev_link]

Flutter plugin to support iOS/macOS, Android and Web sources at https://posthog.com.

## Usage

To use this plugin, add `posthog_flutter` as a [dependency in your pubspec.yaml file](https://pub.dev/packages/posthog_flutter/install).

### Supported methods

| Method                    | Android | iOS/macOS | Web |
| ------------------------- | ------- | --------- | --- |
| `identify`                | X       | X         | X   |
| `capture`                 | X       | X         | X   |
| `screen`                  | X       | X         | X   |
| `alias`                   | X       | X         | X   |
| `getDistinctId`           | X       | X         | X   |
| `reset`                   | X       | X         | X   |
| `disable`                 | X       | X         | X   |
| `enable`                  | X       | X         | X   |
| `debug`                   | X       | X         | X   |
| `register`                | X       | X         | X   |
| `unregister`              | X       | X         | X   |
| `flush`                   | X       | X         |     |
| `isFeatureEnabled`        | X       | X         | X   |
| `reloadFeatureFlags`      | X       | X         | X   |
| `getFeatureFlag`          | X       | X         | X   |
| `getFeatureFlagPayload`   | X       | X         | X   |
| `group`                   | X       | X         | X   |

### Example

```dart
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        // The PosthogObserver records screen views automatically
        PosthogObserver(),
      ],
      home: Scaffold(
        appBar: AppBar(
          title: Text('Posthog example app'),
        ),
        body: Center(
          child: FlatButton(
            child: Text('TRACK ACTION WITH POSTHOG'),
            onPressed: () {
              Posthog().capture(
                eventName: 'ButtonClicked',
                properties: {
                  'foo': 'bar',
                  'number': 1337,
                  'clicked': true,
                },
              );
            },
          ),
        ),
      )
    );
  }
}
```

## Installation

Setup your Android, iOS/macOS and/or web sources as described at Posthog.com and generate your api keys.

Set your Posthog api key and change the automatic event tracking (only for Android and iOS) on if you wish the library to take care of it for you.
Remember that the application lifecycle events won't have any special context set for you by the time it is initialized. If you are using a self hosted instance of Posthog you will need to have the public hostname or ip for your instance as well.

### Android

Automatically:

```xml file=AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.posthog_flutter_example">
    <application>
        <activity>
            [...]
        </activity>
        <meta-data android:name="com.posthog.posthog.API_KEY" android:value="YOUR_API_KEY_GOES_HERE" />
        <!-- or EU Host: 'https://eu.i.posthog.com' -->
        <meta-data android:name="com.posthog.posthog.POSTHOG_HOST" android:value="https://us.i.posthog.com" />
        <meta-data android:name="com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS" android:value="true" />
        <meta-data android:name="com.posthog.posthog.DEBUG" android:value="true" />
    </application>
</manifest>
```

Or manually, disable the auto init:

```xml file=AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.posthog_flutter_example">
    <application>
        <activity>
            [...]
        </activity>
        <meta-data android:name="com.posthog.posthog.AUTO_INIT" android:value="false" />
    </application>
</manifest>
```

And setup the SDK manually:

```dart
Future<void> main() async {
    // init WidgetsFlutterBinding if not yet
    WidgetsFlutterBinding.ensureInitialized();
    final config = PostHogConfig('YOUR_API_KEY_GOES_HERE');
    config.debug = true;
    config.captureApplicationLifecycleEvents = true;
    // or EU Host: 'https://eu.i.posthog.com'
    config.host = 'https://us.i.posthog.com';
    await Posthog().setup(config);
    runApp(MyApp());
}
```

### iOS/macOS

```xml file=Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	[...]
	<key>com.posthog.posthog.API_KEY</key>
	<string>YOUR_API_KEY_GOES_HERE</string>
	<key>com.posthog.posthog.POSTHOG_HOST</key>
	<!-- or EU Host: 'https://eu.i.posthog.com' -->
	<string>https://us.i.posthog.com</string>
	<key>com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS</key>
	<true/>
	<key>com.posthog.posthog.DEBUG</key>
	<true/>
	[...]
</dict>
</plist>
```

### Web

```html file=index.html
<!DOCTYPE html>
<html>
  <head>
    ...
    <script>
      !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.async=!0,p.src=s.api_host+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagPayload reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
      // or EU Host: 'https://eu.i.posthog.com'
      posthog.init('YOUR_WRITE_KEY_GOES_HERE', {api_host: 'https://us.i.posthog.com'})
    </script>
  </head>

  <body>
    ...
  </body>
</html>
```

For more informations please check the [docs](https://posthog.com/docs/libraries/js).

## Issues

Please file any issues, bugs, or feature requests in the [GitHub repo](https://github.com/posthog/posthog-flutter/issues/new).

## Contributing

If you wish to contribute a change to this repo, please send a [pull request](https://github.com/posthog/posthog-flutter/pulls).

## Questions?

### [Check out our community page.](https://posthog.com/posts)

[pubdev_badge]: https://img.shields.io/pub/v/posthog_flutter
[pubdev_link]: https://pub.dev/packages/posthog_flutter
