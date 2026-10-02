[![Package on pub.dev][pubdev_badge]][pubdev_link]

# PostHog Flutter

Please see the main [PostHog docs](https://posthog.com/docs).

Specifically, the [Flutter docs](https://posthog.com/docs/libraries/flutter) details.

## Desktop support

Windows and Linux support the core analytics SDK. Session replay, surveys,
logs, push notifications, and native crash capture are not supported.

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

## Questions?

### [Check out our community page.](https://posthog.com/posts)

[pubdev_badge]: https://img.shields.io/pub/v/posthog_flutter
[pubdev_link]: https://pub.dev/packages/posthog_flutter
