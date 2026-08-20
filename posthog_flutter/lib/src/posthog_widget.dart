import 'package:flutter/foundation.dart' show kIsWeb;
// The replay capturer defines its own ImageInfo; hide Flutter's.
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/util/logging.dart';

import 'replay/change_detector.dart';
import 'replay/native_communicator.dart';
import 'replay/screenshot/screenshot_capturer.dart';

/// Wraps a Flutter app to enable mobile session replay screenshots.
///
/// Place [PostHogWidget] above your app content when `PostHogConfig.sessionReplay`
/// is enabled. The widget captures snapshots from [child] and sends them to the
/// native SDK while session recording is active.
class PostHogWidget extends StatefulWidget {
  /// The widget subtree to include in session replay snapshots.
  final Widget child;

  /// Creates a session replay root widget around [child].
  const PostHogWidget({super.key, required this.child});

  @override
  PostHogWidgetState createState() => PostHogWidgetState();
}

/// State for [PostHogWidget].
class PostHogWidgetState extends State<PostHogWidget> {
  ChangeDetector? _changeDetector;
  ScreenshotCapturer? _screenshotCapturer;
  NativeCommunicator? _nativeCommunicator;

  bool _isCapturing = false;
  bool _disposed = false;

  bool _sampleRequestedDuringCapture = false;

  /// Whether a substitute source (bridge or placeholder) owns the current
  /// episode. Not the same as "occluded": with the bridge off, occlusion is
  /// ignored and Flutter capture keeps running.
  bool _suppressFlutterCapture = false;

  @visibleForTesting
  bool get debugFlutterCaptureSuppressed => _suppressFlutterCapture;

  void _setSuppressFlutterCapture(bool value) {
    _suppressFlutterCapture = value;
    _changeDetector?.suppressForcedFrames = value;
  }

  @override
  void initState() {
    super.initState();

    final config = Posthog().config;
    if (config == null) {
      return;
    }

    // On web, session replay is recorded by posthog-js; this pipeline has no
    // consumer there, so every snapshot it produces is discarded.
    if (!kIsWeb && config.sessionReplay) {
      _initComponents(config);
      _changeDetector?.start();
    }

    PostHogInternalEvents.sessionRecordingActive.addListener(
      _onSessionRecordingChanged,
    );
    PostHogInternalEvents.nativeOcclusionEvent.addListener(
      _onNativeOcclusionChanged,
    );
    PostHogInternalEvents.forceReplaySessionReset.addListener(
      _onForcedReplaySessionReset,
    );
  }

  /// How many poll ticks keep forcing a frame after [_ensureSampleLands], if no
  /// frame has been delivered yet. Each is a throttleDelay apart, so at the
  /// default 1 s cadence this covers windows measured in milliseconds.
  static const _sampleRetryTicks = 3;

  /// Drops the per-session state directly, rather than waiting for a tick to
  /// read the new id. See [PostHogInternalEvents.forceReplaySessionReset].
  void _onForcedReplaySessionReset() {
    _screenshotCapturer?.resetSessionStateIfNeeded(null, force: true);
    // No sample this turn, only the retry budget: at an identity or project
    // boundary the host is usually about to replace the screen, and a frame
    // forced now would record the pre-boundary UI into the session that
    // replaces it. A repaint within the next tick delivers the new session's
    // first frame instead; the budget covers a screen that never repaints.
    _changeDetector?.forceNextTicks(_sampleRetryTicks);
  }

  /// The single way to sample out of band, for callers that need the next frame
  /// recorded and cannot wait for the screen to change on its own.
  ///
  /// Two things swallow such a request and every caller needs cover for both: a
  /// capture already in flight, and a platform briefly not recording when the
  /// sample lands. Hence deferring past the in-flight capture *and* a retry
  /// budget, which delivery cancels.
  void _ensureSampleLands() {
    if (_isCapturing) {
      _sampleRequestedDuringCapture = true;
    } else {
      _changeDetector?.requestImmediateSample();
    }
    _changeDetector?.forceNextTicks(_sampleRetryTicks);
  }

  /// A native screen started/stopped covering Flutter (pushed by the native
  /// detector). On entry: hand off to the bridge, else emit one black
  /// placeholder. On exit: invalidate dedup hashes so the first Flutter frame
  /// isn't dropped. With the bridge off, episodes are ignored.
  Future<void> _onNativeOcclusionChanged() async {
    if (_disposed) {
      return;
    }
    final occluded = PostHogInternalEvents.nativeOcclusionActive;
    final episode = PostHogInternalEvents.nativeOcclusionEpisode;
    final bridgeFailed = PostHogInternalEvents.nativeBridgeFailed;
    // Released before the config is read: an episode ends whether or not the SDK
    // is currently set up, and native pushes exactly one end event. Dropping it
    // between close() and setup() would strand capture suppressed for the life
    // of the app, leaving the next session's recording blank.
    if (!occluded) {
      printIfDebug(
          'Native occlusion ended (episode $episode): resuming Flutter capture.');
      _setSuppressFlutterCapture(false);
      _screenshotCapturer?.onOcclusionEnded();
      // Without a sample here the replay would stay on the episode's last frame
      // until the app happens to render again.
      _ensureSampleLands();
      return;
    }
    final replayConfig = Posthog().config?.sessionReplayConfig;
    if (replayConfig == null) {
      return;
    }
    if (!replayConfig.captureNativeScreens) {
      // Fail open in case the bridge was toggled off mid-episode.
      printIfDebug('Native occlusion started (episode $episode): '
          'captureNativeScreens is off, keeping Flutter capture.');
      _setSuppressFlutterCapture(false);
      return;
    }
    // Suppress synchronously so no covered frame slips out during the handshake.
    _setSuppressFlutterCapture(true);
    if (!bridgeFailed) {
      final accepted =
          await _nativeCommunicator?.enableNativeBridge(episode: episode) ??
              false;
      if (_disposed ||
          !PostHogInternalEvents.episodeStillCurrent(episode, occluded: true)) {
        return;
      }
      if (accepted) {
        printIfDebug('Native occlusion started (episode $episode): '
            'bridged to native capture.');
        return;
      }
    }
    printIfDebug(
        'Native occlusion started (episode $episode): emitting placeholder.');
    final imageInfo = await _screenshotCapturer?.buildOcclusionPlaceholder();
    if (imageInfo != null && !_disposed) {
      // A placeholder is only valid while its own episode is occluding.
      await _sendSnapshot(
        imageInfo,
        isStillValid: () => _stillValid(imageInfo, episode, occluded: true),
      );
    }
  }

  /// A frame may only ship while the world it was captured in is still current:
  /// the same occlusion episode and the same replay session. The send resolves
  /// the session, so a stale frame would land in the new session ahead of the
  /// meta event that session has not sent yet.
  bool _stillValid(ImageInfo imageInfo, int episode, {required bool occluded}) {
    return PostHogInternalEvents.episodeStillCurrent(episode,
            occluded: occluded) &&
        (_screenshotCapturer?.sessionStillCurrent(imageInfo) ?? false);
  }

  void _initComponents(PostHogConfig config) {
    _screenshotCapturer = ScreenshotCapturer(
      config,
      // The observing tick's own frame can still be dropped, and on a static
      // screen no further tick would run. This fires from inside that tick, so
      // it costs one redundant capture when the frame did deliver — cheaper
      // than waiting a throttleDelay for the retries to repair it.
      onSessionRotated: _ensureSampleLands,
    );
    _nativeCommunicator = NativeCommunicator();
    _changeDetector = ChangeDetector(
      _onChangeDetected,
      interval: config.sessionReplayConfig.throttleDelay,
    )..suppressForcedFrames = _suppressFlutterCapture;
  }

  void _onSessionRecordingChanged() {
    if (PostHogInternalEvents.sessionRecordingActive.value) {
      _startRecording();
    } else {
      _stopRecording();
    }
  }

  void _startRecording() {
    if (kIsWeb) {
      return;
    }

    final config = Posthog().config;
    if (config == null) {
      return;
    }

    if (_changeDetector == null) {
      _initComponents(config);
    }

    _changeDetector?.start();
  }

  void _stopRecording() {
    _changeDetector?.stop();
    _screenshotCapturer?.cancel();
  }

  // This works as onRootViewsChangedListeners
  void _onChangeDetected() {
    if (_isCapturing) {
      return;
    }
    // The covered Flutter tree must not be captured while a substitute source
    // owns the episode: Flutter keeps rendering (spinners, clocks) behind an
    // opaque cover, and those frames would interleave with bridged ones.
    if (_suppressFlutterCapture) {
      return;
    }

    _generateSnapshot();
  }

  Future<void> _generateSnapshot() async {
    if (_disposed) {
      return;
    }

    // Ensure no asynchronous calls occur before this function,
    // as it relies on a consistent state.
    _isCapturing = true;
    final episode = PostHogInternalEvents.nativeOcclusionEpisode;
    // Live value (not false): with the bridge off, occlusion is ignored and
    // covered frames are still recorded — hardcoding false would drop them.
    final occluded = PostHogInternalEvents.nativeOcclusionActive;

    try {
      final imageInfo = await _screenshotCapturer?.captureScreenshot();
      // Refresh before the null check: a dropped frame on a static captured-view
      // screen must still keep forced frames scheduled.
      _changeDetector?.hasCapturedPlatformViews =
          _screenshotCapturer?.hasCapturedPlatformViews ?? false;
      if (imageInfo == null || _disposed) {
        return;
      }
      final delivered = await _sendSnapshot(
        imageInfo,
        isStillValid: () => _stillValid(imageInfo, episode, occluded: occluded),
      );
      if (delivered) {
        // Keyed on delivery: a frame dropped for belonging to the world it
        // started in must not cancel the retries covering what replaced it.
        _changeDetector?.cancelForcedTicks();
      }
    } finally {
      _isCapturing = false;
      if (_sampleRequestedDuringCapture) {
        _sampleRequestedDuringCapture = false;
        _changeDetector?.requestImmediateSample();
      }
    }
  }

  /// Sends [imageInfo] (meta first when flagged) and commits the capturer's
  /// delivery state only after delivery — the single delivery→commit path.
  /// [isStillValid] is re-checked after every await so a stale frame never
  /// ships into another episode. Returns whether the frame was delivered.
  Future<bool> _sendSnapshot(
    ImageInfo imageInfo, {
    required bool Function() isStillValid,
  }) async {
    if (_disposed || !isStillValid()) {
      return false;
    }
    if (imageInfo.shouldSendMetaEvent) {
      await _nativeCommunicator?.sendMetaEvent(
        width: imageInfo.width,
        height: imageInfo.height,
        screen: Posthog().currentScreen,
      );
      if (_disposed || !isStillValid()) {
        return false;
      }
    }

    await _nativeCommunicator?.sendFullSnapshot(
      imageInfo.imageBytes,
      id: imageInfo.id,
      x: imageInfo.x,
      y: imageInfo.y,
    );
    // Also guards the commit below: a validity flip means a boundary handler
    // already re-armed, and committing now would clobber it.
    if (_disposed || !isStillValid()) {
      return false;
    }
    _screenshotCapturer?.confirmDelivered(
      imageInfo.id,
      metaSent: imageInfo.shouldSendMetaEvent,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: PostHogMaskController.instance.containerKey,
      child: Column(
        children: [Expanded(child: Container(child: widget.child))],
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;

    PostHogInternalEvents.sessionRecordingActive.removeListener(
      _onSessionRecordingChanged,
    );
    PostHogInternalEvents.nativeOcclusionEvent.removeListener(
      _onNativeOcclusionChanged,
    );
    PostHogInternalEvents.forceReplaySessionReset.removeListener(
      _onForcedReplaySessionReset,
    );

    _changeDetector?.stop();
    _changeDetector = null;
    _screenshotCapturer?.cancel();
    _screenshotCapturer = null;
    _nativeCommunicator = null;

    super.dispose();
  }
}
