---
"posthog_flutter": minor
---

Add structured logging. You can now send logs to PostHog from your Flutter app and see them next to your events and session replays — great for debugging what actually happened in production.

Use `logger` for everyday logging:

```dart
Posthog().logger.info('checkout completed', {'order_id': 'ord_789'});
Posthog().logger.warn('retrying payment', {'attempt': 2});
Posthog().logger.error('payment failed', {'error_code': 'E001'});
```

Levels are `trace`, `debug`, `info`, `warn`, `error`, and `fatal`, and you can attach any JSON-friendly attributes. When you need to pick the level at runtime, use `captureLog` instead:

```dart
await Posthog().captureLog(
  body: 'request finished',
  level: ok ? PostHogLogSeverity.info : PostHogLogSeverity.error,
  attributes: {'duration_ms': 142},
);
```

Every log is automatically tagged with the current distinct ID, session, screen, app state, and active feature flags, so you get that context for free.

Configure it (everything optional — anything you skip keeps a sensible default) on `config.logs`:

```dart
config.logs
  ..serviceName = 'checkout-app'
  ..environment = 'production'
  // Redact or drop logs before they leave the device:
  ..beforeSend = [
    (record) {
      record.attributes?.remove('password');
      return record;
    },
  ];
```

You can also tune batching and rate limiting (`flushInterval`, `flushAt`, `maxBatchSize`, `maxBufferSize`, `rateCapMaxLogs`, `rateCapWindow`) if the defaults don't suit you. Works on iOS, Android, and web.

**Good to know:**

- Distributed tracing: `captureLog` also accepts optional `traceId`, `spanId`, and `traceFlags` to correlate a log with a trace.
- On Flutter web, set your log options in your own `posthog.init({...})` call (Flutter attaches to your existing posthog-js instance) — your Dart `beforeSend` still runs.
- Android: needs `posthog-android` `3.48.0` or newer, which this package now requires for you.
