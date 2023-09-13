# Posthog plugin

![Pub Version](https://img.shields.io/pub/v/posthog_flutter)

Flutter plugin to support iOS, Android and Web sources at https://posthog.com.

## Usage

To use this plugin, add `posthog_flutter` as a [dependency in your pubspec.yaml file](https://flutter.io/platform-plugins/).

### Supported methods

| Method              | Android | iOS | Web |
| ------------------  | ------- | --- | --- |
| `identify`          | X       | X   | X   |
| `capture`           | X       | X   | X   |
| `screen`            | X       | X   | X   |
| `alias`             | X       | X   | X   |
| `getAnonymousId`    | X       | X   | X   |
| `reset`             | X       | X   | X   |
| `disable`           | X       | X   |     |
| `enable`            | X       | X   |     |
| `debug`             | X\*     | X   | X   |
| `setContext`        | X       | X   |     |
| `isFeatureEnabled`  | X       | X   | X   |
| `reloadFeatureFlags`| X       | X   | X   |

\* Debugging must be set as a configuration parameter in `AndroidManifest.xml` (see below). The official posthog library does not offer the debug method for Android.

### Example

```dart
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Posthog().screen(
      screenName: 'Example Screen',
    );
    return MaterialApp(
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
      ),
      navigatorObservers: [
        PosthogObserver(),
      ],
    );
  }
}
```

## Installation

Setup your Android, iOS and/or web sources as described at Posthog.com and generate your api keys.

Set your Posthog api key and change the automatic event tracking (only for Android and iOS) on if you wish the library to take care of it for you.
Remember that the application lifecycle events won't have any special context set for you by the time it is initialized. If you are using a self hosted instance of Posthog you will need to have the public hostname or ip for your instance as well.

### Android

#### AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.posthog.posthog_flutter_example">
    <application>
        <activity>
            [...]
        </activity>
        <meta-data android:name="com.posthog.posthog.API_KEY" android:value="YOUR_API_KEY_GOES_HERE" />
        <meta-data android:name="com.posthog.posthog.POSTHOG_HOST" android:value="https://eu.posthog.com" />
        <meta-data android:name="com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS" android:value="false" />
        <meta-data android:name="com.posthog.posthog.DEBUG" android:value="false" />
    </application>
</manifest>
```

### iOS

#### Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	[...]
	<key>com.posthog.posthog.API_KEY</key>
	<string>YOUR_API_KEY_GOES_HERE</string>
	<key>com.posthog.posthog.POSTHOG_HOST</key>
	<string>https://eu.posthog.com</string>
	<key>com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS</key>
	<false/>
	[...]
</dict>
</plist>
```

### Web

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>example</title>
</head>
<body>
  <script>
    !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.async=!0,p.src=s.api_host+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
      posthog.init("YOUR_WRITE_KEY_GOES_HERE", {api_host: 'https://eu.posthog.com'});
  </script>
<script src="main.dart.js" type="application/javascript"></script>
</body>
</html>
```

For more informations please check: https://posthog.com/docs/integrations/js-integration

## Issues

Please file any issues, bugs, or feature requests in the [GitHub repo](https://github.com/posthog/posthog-flutter/issues/new).

## Contributing

If you wish to contribute a change to this repo, please send a [pull request](https://github.com/posthog/posthog-flutter/pulls).

## Deploying to pub.dev

- [Developing and publishing packages & plugins](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#publish)
- [Publishing packages](https://dart.dev/tools/pub/publishing)

## Questions?

### [Join our Slack community.](https://join.slack.com/t/posthogusers/shared_invite/enQtOTY0MzU5NjAwMDY3LTc2MWQ0OTZlNjhkODk3ZDI3NDVjMDE1YjgxY2I4ZjI4MzJhZmVmNjJkN2NmMGJmMzc2N2U3Yjc3ZjI5NGFlZDQ)
