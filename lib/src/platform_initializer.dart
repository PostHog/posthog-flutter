import 'package:posthog_flutter/src/posthog_options.dart';

abstract class PlatformInitializer {
  Future<void> init(String apiKey, PostHogOptions options);
}
