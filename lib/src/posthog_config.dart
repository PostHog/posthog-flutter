import 'package:posthog_flutter/src/posthog_options.dart';

class PostHogConfig {
  static final PostHogConfig _instance = PostHogConfig._internal();

  factory PostHogConfig() {
    return _instance;
  }

  PostHogConfig._internal();

  late PostHogOptions options;
}
