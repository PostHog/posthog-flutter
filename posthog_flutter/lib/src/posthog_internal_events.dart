import 'package:flutter/foundation.dart';
// ignore: unnecessary_import
import 'package:meta/meta.dart';

@internal
class PostHogInternalEvents {
  PostHogInternalEvents._(); // private init

  static final sessionRecordingActive = ValueNotifier<bool>(false);

  /// Drops the replay capture's per-session state without waiting for a capture
  /// tick to observe a new session id.
  ///
  /// A tick would usually notice on its own, one frame late. It never notices
  /// when the recording restarts while the platform keeps the same session id —
  /// Android returns early from `PostHog.startSessionReplay` while recording is
  /// already active, so nothing rotates — and only this bump re-arms the meta
  /// event. (posthog-android 3.58.0)
  static final forceReplaySessionReset = ValueNotifier<int>(0);

  static void requestReplaySessionReset() => forceReplaySessionReset.value++;

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
