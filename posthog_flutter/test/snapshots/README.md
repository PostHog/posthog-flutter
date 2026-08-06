# Event shape snapshots

These fixtures pin the latest deterministic boundary owned by the Flutter package: public Dart API calls after Flutter-side enrichment, `beforeSend` processing, property normalization, and conversion to platform-channel method arguments.

The embedded Android and Apple SDKs add device, identity, session, and other system properties, then build and encode ingestion and feature-flag network requests. Flutter does not receive those final events or decoded wire requests, so their snapshots belong in the native SDK repositories. Flutter web similarly delegates final enrichment and serialization to posthog-js. These fixtures intentionally do not duplicate those downstream snapshots.

To accept an intentional Flutter-owned shape change after reviewing the diff, run:

```sh
flutter test test/event_shape_snapshot_test.dart \
  --dart-define=UPDATE_EVENT_SHAPE_SNAPSHOTS=true
```
