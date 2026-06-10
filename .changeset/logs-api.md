---
"posthog_flutter": minor
---

Add structured logging. Send logs to PostHog from your Flutter app and see them next to your events and session replays.

```dart
Posthog().logger.info('checkout completed', {'order_id': 'ord_789'});
Posthog().logger.error('payment failed', {'error_code': 'E001'});

// Or pick the level at runtime:
await Posthog().captureLog(body: 'request finished', level: PostHogLogSeverity.warn);
```

Levels: `trace`, `debug`, `info`, `warn`, `error`, `fatal`. Configure service identity, redaction (`beforeSend`), and batching/rate-cap tuning on `config.logs` — all optional, with sensible native defaults. Works on iOS, Android, and web.

See https://posthog.com/docs/logs for details.
