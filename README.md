[![Package on pub.dev][pubdev_badge]][pubdev_link]

# PostHog Flutter

Please see the main [PostHog docs](https://posthog.com/docs).

Specifically, the [Flutter docs](https://posthog.com/docs/libraries/flutter) details.

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

## Background isolate errors

`captureIsolateErrors` only monitors the isolate where PostHog is set up, normally
the main isolate. For each background isolate, call `addPostHogErrorListener()`
from the main isolate after initializing PostHog:

```dart
import 'dart:isolate';
import 'package:posthog_flutter/posthog_flutter.dart';

final isolate = await Isolate.spawn(worker, message, paused: true);
final listener = isolate.addPostHogErrorListener();
isolate.resume(isolate.pauseCapability!);
```

Starting paused prevents errors before the listener is added. Uncaught errors are
forwarded with their background stack trace and debug name, and are reported as
unhandled. Dart sends error strings, not the original exception objects.

The listener does not require `captureIsolateErrors` to be enabled. It is removed
and its port closed automatically when the isolate exits. To stop forwarding
earlier and close its port explicitly:

```dart
isolate.removePostHogErrorListener(listener);
```

Repeated removal is safe. Add only once per isolate to avoid duplicate reports.
Existing error listeners and whether errors terminate the isolate are unchanged.

Flutter web does not support isolates. For `compute()` or `Isolate.run()`, catch
errors from the returned future and report them with
`Posthog().captureException(error: error, stackTrace: stackTrace)`.

## Questions?

### [Check out our community page.](https://posthog.com/posts)

[pubdev_badge]: https://img.shields.io/pub/v/posthog_flutter
[pubdev_link]: https://pub.dev/packages/posthog_flutter
