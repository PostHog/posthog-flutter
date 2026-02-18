import 'package:flutter/foundation.dart';
// ignore: unnecessary_import
import 'package:meta/meta.dart';

@internal
class PostHogInternalEvents {
  PostHogInternalEvents._(); // private init

  static final sessionRecordingActive = ValueNotifier<bool>(false);
}
