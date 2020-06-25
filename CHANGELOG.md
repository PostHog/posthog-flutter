## 2.1.1

- fixed `context` overwriting (using `posthog.setContext(...)`) for `iOS` devices

## 2.1.0

- added `ENABLE_BRANCH_IO_INTEGRATION` configuration option

## 2.0.2

- added `disable` and `enable` methods for Android
- added `DEBUG` configuration option for Android (used on `AndroidManifest.xml`)

## 2.0.1

- fixed method channel issue

## 2.0.0

### BREAKING CHANGE

- removed `putDeviceToken` call
- added `setContext` as a better and more general approach to setting context variables

### Feature

- added support to the new [Android plugins APIs](https://flutter.dev/docs/development/packages-and-plugins/plugin-api-migration)

## 1.0.0

### BREAKING CHANGE

- the name was changed from `FlutterPosthog` to `Posthog`
- set flutter version to `>=1.12.13+hotfix.4 <2.0.0`

### Feature

- added web support

## 0.0.8

- added support for integration options in Android (iOS was already supported in previous versions)
- added a configuration parameter for enabling/disabling automatic application lifecycle tracking (only for Android, iOS)
- removed `Application Started` tracking event from Android plugin registration

## 0.0.7

- initialize plugin along with FirebaseMessaging

## 0.0.6

- added support for device token

## 0.0.5

- improved dependencies

## 0.0.4

- added NavigatorObserver to automatically track named screen transitions

## 0.0.3

- added package fixes and missing license

## 0.0.2

- extended README

## 0.0.1

- initial implementation to support general Posthog API for iOS and Android
