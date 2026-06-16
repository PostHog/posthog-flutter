---
"posthog_flutter": minor
---

Add `addExceptionStep`, recording breadcrumb-style context records that attach to every captured `$exception` as `$exception_steps`, giving the error-tracking UI a timeline of recent activity leading up to each error.

Steps accumulate in a rolling, byte-bounded buffer owned by the embedded native SDK, so they also survive native fatal crashes and attach to the crash `$exception` reported on the next launch. The buffer rotates only by byte-budget eviction and is not cleared by a capture or an identity change. Configure it on `config.errorTrackingConfig.exceptionSteps` (`enabled`, `maxBytes`).

```dart
Posthog().addExceptionStep('User tapped Checkout', properties: {'screen': 'cart'});
```

Requires `posthog-android` and `posthog-ios` versions that support exception steps. On web, steps are forwarded to posthog-js.
