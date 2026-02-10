import 'package:flutter/foundation.dart';

@internal
class PostHogInternalEvents {
  PostHogInternalEvents._(); // private init

  static final sessionRecordingActive = ValueNotifier<bool>(false);
}
