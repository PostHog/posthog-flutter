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
with executable-name fallbacks
when that metadata is unavailable.

Await `Posthog().setup(config)` to finish initialization. If the application
support directory is unavailable, desktop state stays in memory and is lost
when the SDK closes or the app exits.

## Questions?

### [Check out our community page.](https://posthog.com/posts)

[pubdev_badge]: https://img.shields.io/pub/v/posthog_flutter
[pubdev_link]: https://pub.dev/packages/posthog_flutter
