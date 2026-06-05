---
"posthog_flutter": minor
---

Add `setPersonPropertiesForFlags`, `resetPersonPropertiesForFlags`, `setGroupPropertiesForFlags`, and `resetGroupPropertiesForFlags`, bringing the Flutter SDK to parity with the native iOS/Android and JS SDKs.

These set person/group properties that are sent inline with the next feature flag evaluation request, so flags targeting those properties can be evaluated immediately — without enqueuing a `$set` event or waiting for it to be ingested into the person store. By default they reload feature flags and the returned `Future` completes only after the reload finishes, so the next `getFeatureFlag`/`getFeatureFlagResult` reflects the updated properties. Pass `reloadFeatureFlags: false` to skip the reload.

```dart
await Posthog().setPersonPropertiesForFlags({
  "storefront_country": "US",
  "superwall_demand_score": 88,
});
final result = await Posthog().getFeatureFlagResult("my_flag");
```
