[![Package on pub.dev][pubdev_badge]][pubdev_link]

# PostHog Flutter

Please see the main [PostHog docs](https://posthog.com/docs).

Specifically, the [Flutter docs](https://posthog.com/docs/libraries/flutter) details.

## Android background Flutter engines and error tracking

A plugin-created headless Flutter engine runs Dart in a separate isolate. Error
handlers installed by `Posthog().setup()` in the foreground isolate do **not**
observe that engine's errors. Native Android exception capture covers Java/Kotlin
errors, not uncaught Dart errors in the headless engine.

If your background plugin invokes a Dart entrypoint, initialize PostHog **inside
that entrypoint** (after the engine has registered the PostHog plugin), before
starting work that may fail. Use the same project token and host as the app:

```dart
@pragma('vm:entry-point')
Future<void> backgroundTask() async {
  final config = PostHogConfig('YOUR_PROJECT_TOKEN');
  config.errorTrackingConfig.capturePlatformDispatcherErrors = true;
  await Posthog().setup(config);

  // Run the background task here. Report exceptions you catch yourself with
  // Posthog().captureException(error: error, stackTrace: stackTrace).
}
```

Register `backgroundTask` according to the background plugin's instructions;
PostHog cannot register another plugin's callback or discover its engine. Setup
only installs handlers in the isolate that calls it. Alternatively,
`captureIsolateErrors` adds a listener to that same isolate; enabling both hooks
may report the same uncaught error twice. `Isolate.spawn` workers likewise need
explicit handling (for example, pass an `onError` port to the parent and report
there). A plugin that catches/logs its own errors must call
`captureException` from its handler; uncaught-error hooks cannot see handled
exceptions. If the plugin does not run app Dart code in its background engine,
its integration must forward the error to app code or report it itself. On Android,
engines share the process-wide native PostHog client; do not call `Posthog().close()`
just because the background callback finishes while the foreground app is running.

## Desktop support

Windows and Linux support is experimental and enabled by default. They support
the core analytics SDK. Session replay, surveys, logs, push notifications, and
native crash capture are not supported.

Apps that call `Posthog().setup(config)` will start tracking on Windows
and Linux. To disable the SDK on these platforms without
changing behavior on other platforms, set `config.enableWindowsAndLinux = false`
before setup. Close the SDK before changing this setting and setting up again.

Desktop state is stored under `posthog/<project token>` in the application
support directory returned by Flutter's Windows/Linux `path_provider`
implementations. Keep the application's storage identity stable across releases:
Windows uses the company/product metadata, and Linux uses the application ID,
with executable-name fallbacks when that metadata is unavailable. On Linux,
`path_provider` also reuses an existing executable-name directory if the
application-ID directory does not exist.

Await `Posthog().setup(config)` to finish initialization. If the application
support directory is unavailable, desktop state stays in memory and is lost
when the SDK closes or the app exits. If an I/O error prevents reading an
existing state file, that client keeps state changes in memory and leaves the
file untouched. A new client can try reading the file again. Corrupt file
contents reset the state to defaults; the next state write replaces the file.

`Posthog().close()` makes one attempt to send the queued events and waits for it
for up to two seconds. Events it could not send stay on disk and go out with the
next client, or are lost when state is kept in memory. Closing the app window
does not call `close()`, but the SDK also sends the queue whenever the app
becomes inactive.

## Questions?

### [Check out our community page.](https://posthog.com/posts)

[pubdev_badge]: https://img.shields.io/pub/v/posthog_flutter
[pubdev_link]: https://pub.dev/packages/posthog_flutter
