# Posthog plugin

![Pub Version](https://img.shields.io/pub/v/flutter_posthog)

Flutter plugin to support iOS, Android and Web sources at https://posthog.com.

## Usage

To use this plugin, add `flutter_posthog` as a [dependency in your pubspec.yaml file](https://flutter.io/platform-plugins/).

### Supported methods

| Method           | Android | iOS | Web |
| ---------------- | ------- | --- | --- |
| `identify`       | X       | X   | X   |
| `capture`        | X       | X   | X   |
| `screen`         | X       | X   | X   |
| `alias`          | X       | X   | X   |
| `getAnonymousId` | X       | X   | X   |
| `reset`          | X       | X   | X   |
| `disable`        | X       | X   |     |
| `enable`         | X       | X   |     |
| `debug`          | X\*     | X   | X   |
| `setContext`     | X       | X   |     |

\* Debugging must be set as a configuration parameter in `AndroidManifest.xml` (see below). The official posthog library does not offer the debug method for Android.

### Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_posthog/flutter_posthog.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Posthog.screen(
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
              Posthog.capture(
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

Setup your Android, iOS and/or web sources as described at Posthog.com and generate your write keys.

Set your Posthog write key and change the automatic event tracking (only for Android and iOS) on if you wish the library to take care of it for you.
Remember that the application lifecycle events won't have any special context set for you by the time it is initialized. If you are using a self hosted instance of Posthog you will need to have the public hostname or ip for your instance as well.

### Android

#### AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.posthog.flutter_posthog_example">
    <application>
        <activity>
            [...]
        </activity>
        <meta-data android:name="com.posthog.posthog.API_KEY" android:value="YOUR_API_KEY_GOES_HERE" />
        <meta-data android:name="com.posthog.posthog.POSTHOG_HOST" android:value="https://app.posthog.com" />
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
	<string>https://app.posthog.com</string>
	<key>com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS</key>
	<false/>
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
    [...]
  </head>
  <body>
    <script>
      !function(){ ...;
        posthog.init("YOUR_API_KEY_GOES_HERE", {api_host: 'https://app.posthog.com'});
        posthog.page();
      }}();
    </script>
    <script src="main.dart.js" type="application/javascript"></script>
  </body>
</html>
```

For more informations please check: https://posthog.com/docs/integrations/js-integration

## Sending device tokens strings for push notifications

Posthog integrates with 3rd parties that allow sending push notifications.
In order to do that you will need to provide it with the device token string - which can be obtained using one of the several Flutter libraries.

As soon as you obtain the device token string, you need to add it to Posthog's context by calling `setContext` and then emit a tracking event named `Application Opened` or `Application Installed`. The tracking event is needed because it is the [only moment when Posthog propagates it to 3rd parties](https://posthog.com/docs/connections/destinations/catalog/customer-io/).

Both calls (`setContext` and `track`) can be done sequentially at startup time, given that the token exists.
Nonetheless, if you don't want to delay the token propagation and don't mind having an extra `Application Opened` event in the middle of your app's events, it can be done right away when the token is acquired.

```dart
await Posthog.setContext({
  'device': {
    'token': yourTokenString
  },
});

// the token is only propagated when one of two events are called:
// - Application Installed
// - Application Opened
await Posthog.capture(eventName: 'Application Opened');
```

A few important points:

- The token is propagated as-is to Posthog through the context field, without any manipulation or intermediate calls to Posthog's libraries. Strucutred data - such as APNs - need to be properly converted to its string representation beforehand
- On iOS, once the `device.token` is set, calling `setContext({})` will _not_ clean up its value. This occurs due to the existence of another method from posthog's library that sets the device token for Apple Push Notification service (APNs )
- `setContext` always overrides any previous values that were set in a previous call to `setContext`
- `setContext` is not persisted after the application is closed

## Issues

Please file any issues, bugs, or feature requests in the [GitHub repo](https://github.com/posthog/flutter-posthog/issues/new).

## Contributing

If you wish to contribute a change to this repo, please send a [pull request](https://github.com/posthog/flutter-posthog/pulls).
