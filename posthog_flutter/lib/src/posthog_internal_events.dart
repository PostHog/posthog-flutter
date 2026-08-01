import 'package:flutter/foundation.dart';
// ignore: unnecessary_import
import 'package:meta/meta.dart';

@internal
class PostHogInternalEvents {
  PostHogInternalEvents._(); // private init

  static final sessionRecordingActive = ValueNotifier<bool>(false);

  /// Drops the replay capture's per-session state right now, without waiting
  /// for the capture path to observe a new session id. Bumped for the session
  /// changes Dart learns about first: `reset()`, `close()`, and a start that
  /// does not resume the current session — which must not inherit the previous
  /// session's meta latch even on a platform that kept the same session id.
  ///
  /// A missed bump usually self-heals: the capture tick re-reads the native
  /// session id every throttle interval, so a rotation is adopted within one
  /// tick, costing at most one frame shipped into the new session without a
  /// meta event ahead of it. It does not self-heal when the platform restarts
  /// recording while keeping the same session id — Android returns early from
  /// `PostHog.startSessionReplay` when recording is already active — because
  /// the tick sees no change and only this bump re-arms the meta event.
  ///
  /// Bump it through [requestReplaySessionReset].
  static final forceReplaySessionReset = ValueNotifier<int>(0);

  /// Bumps [forceReplaySessionReset]; see there for when it is required.
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
