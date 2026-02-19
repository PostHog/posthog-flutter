{
  "steps": [
    "Record current branch (main) and create a new branch: docs/backfill-public-api-dartdoc",
    "Add dartdoc comments to PostHogPersonProfiles enum in lib/src/posthog_config.dart (line 13) - document each value: never, always, identifiedOnly",
    "Add dartdoc comments to PostHogDataMode enum in lib/src/posthog_config.dart (line 15) - document each value: wifi, cellular, any",
    "Add class-level dartdoc to PostHogConfig class (line 17) describing its role as the main configuration object for the PostHog SDK",
    "Add dartdoc comments to undocumented PostHogConfig properties: apiKey (line 18), host (line 19), flushAt (line 20), maxQueueSize (line 21), maxBatchSize (line 22), flushInterval (line 23), sendFeatureFlagEvents (line 24), preloadFeatureFlags (line 25), captureApplicationLifecycleEvents (line 26), debug (line 28), optOut (line 29), personProfiles (line 30)",
    "Add class-level dartdoc to Posthog class in lib/src/posthog.dart (line 13) describing it as the main entry point singleton for the PostHog SDK",
    "Add dartdoc to undocumented Posthog.flush() method (line 313)",
    "Add class-level dartdoc to PosthogObserver class in lib/src/posthog_observer.dart (line 18) describing it as a NavigatorObserver for automatic screen tracking",
    "Add dartdoc to ScreenNameExtractor typedef in lib/src/posthog_observer.dart (line 7)",
    "Add dartdoc to defaultNameExtractor function in lib/src/posthog_observer.dart (line 14)",
    "Add dartdoc to defaultPostHogRouteFilter function in lib/src/posthog_observer.dart (line 16)",
    "Add class-level dartdoc to PostHogWidget in lib/src/posthog_widget.dart (line 12) describing its role as the root widget wrapper for session replay",
    "Add class-level dartdoc to PostHogMaskWidget in lib/src/replay/mask/posthog_mask_widget.dart (line 3) describing its role in masking sensitive content during session replay",
    "Add class-level dartdoc to PostHogSessionReplayConfig in lib/src/posthog_config.dart (line 163)",
    "Add class-level dartdoc to PostHogErrorTrackingConfig in lib/src/posthog_config.dart (line 198)",
    "Run dart analyze to verify no issues were introduced",
    "Commit all changes with the message 'docs: add dartdoc comments to public API surface' and required git trailers",
    "Open a PR targeting main with a summary of the documentation additions",
    "Switch back to main branch"
  ],
  "files": [
    "lib/src/posthog_config.dart",
    "lib/src/posthog.dart",
    "lib/src/posthog_observer.dart",
    "lib/src/posthog_widget.dart",
    "lib/src/replay/mask/posthog_mask_widget.dart"
  ],
  "description": "Add missing dartdoc comments to all public API members exported from posthog_flutter.dart. This covers: class-level docs for Posthog, PostHogConfig, PosthogObserver, PostHogWidget, PostHogMaskWidget, PostHogSessionReplayConfig, and PostHogErrorTrackingConfig; property docs for the 12 undocumented PostHogConfig fields; enum docs for PostHogPersonProfiles and PostHogDataMode; typedef docs for ScreenNameExtractor; and method docs for Posthog.flush(). Survey model classes are internal (not exported) and are excluded from scope."
}
