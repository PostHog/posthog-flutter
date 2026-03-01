/// PostHog analytics SDK for Dart.
///
/// Provides product analytics and feature flags functionality.
///
/// ```dart
/// final posthog = PostHog('phc_your_api_key');
/// posthog.capture('event_name', properties: {'key': 'value'});
/// ```
library;

export 'src/posthog_client.dart' show PostHog;
export 'src/storage.dart' show PostHogStorage, InMemoryStorage;
export 'src/config.dart'
    show
        PostHogConfig,
        PostHogCaptureOptions,
        BootstrapConfig,
        PostHogPersonProfiles,
        BeforeSendFn,
        CaptureEvent;
export 'src/feature_flags.dart'
    show
        FeatureFlagValue,
        FeatureFlagDetail,
        FeatureFlagMetadata,
        EvaluationReason,
        PostHogFeatureFlagResult,
        PostHogFeatureFlagResultOptions,
        PostHogFlagsResponse;
export 'src/persistence.dart' show PostHogPersistedProperty;
export 'src/file_storage.dart' show FileStorage;

// For custom implementations that subclass PostHogCore, import directly:
//   import 'package:posthog_dart/src/posthog_core.dart';
//   import 'package:posthog_dart/src/http.dart';
