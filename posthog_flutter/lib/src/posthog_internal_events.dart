import 'package:flutter/foundation.dart';
// ignore: unnecessary_import
import 'package:meta/meta.dart';

@internal
class PostHogInternalEvents {
  PostHogInternalEvents._(); // private init

  static final sessionRecordingActive = ValueNotifier<bool>(false);

  /// Occlusion episode protocol, pushed by the native side. A monotonic
  /// counter (not a bool, which would dedupe repeated states and swallow e.g. a
  /// bridge-failure re-push). Current state is in [nativeOcclusionActive] /
  /// [nativeOcclusionEpisode] / [nativeBridgeFailed]; async work captures the
  /// episode id at start and re-validates it at each send, to tell "still
  /// episode A" from "a new episode started mid-flight".
  static final nativeOcclusionEvent = ValueNotifier<int>(0);

  static bool nativeOcclusionActive = false;
  static int nativeOcclusionEpisode = 0;
  static bool nativeBridgeFailed = false;

  /// Whether an async operation started in [episode]/[occluded] is still acting
  /// on the world it saw — the episode id distinguishes "still episode A" from
  /// "a new episode started mid-flight".
  static bool episodeStillCurrent(int episode, {required bool occluded}) {
    return nativeOcclusionEpisode == episode &&
        nativeOcclusionActive == occluded;
  }
}
