import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Element, WidgetsBinding;
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/element_parsers/element_data.dart';
import 'package:posthog_flutter/src/replay/image_extension.dart';
import 'package:posthog_flutter/src/replay/mask/image_mask_painter.dart';
import 'package:posthog_flutter/src/replay/mask/posthog_mask_controller.dart';
import 'package:posthog_flutter/src/replay/native_communicator.dart';
import 'package:posthog_flutter/src/replay/screenshot/snapshot_manager.dart';
import 'package:posthog_flutter/src/replay/size_extension.dart';
import 'package:posthog_flutter/src/util/logging.dart';

class ImageInfo {
  final int id;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool shouldSendMetaEvent;
  final Uint8List imageBytes;

  /// Which run of the capturer's per-session state this frame was built in.
  /// A frame naming no session cannot be told apart from a fresh one by id
  /// alone, so the generation is what separates them.
  final int generation;

  /// The replay session this frame was captured under, so the sender can drop
  /// it if the session rotates mid-flight.
  final String? sessionId;

  ImageInfo(
    this.id,
    this.x,
    this.y,
    this.width,
    this.height,
    this.shouldSendMetaEvent,
    this.imageBytes, {
    required this.sessionId,
    required this.generation,
  });
}

class ViewTreeSnapshotStatus {
  bool sentMetaEvent = false;

  /// Hash of the last captured raw RGBA image bytes.
  /// We store only a hash instead of the full byte array to avoid
  /// holding ~8MB+ of raw pixel data in memory permanently.
  int? imageBytesHash;

  int? compositedBytesHash;

  ViewTreeSnapshotStatus(this.sentMetaEvent);
}

/// A masked platform view, kept with its [RenderBox] so its mask can be
/// re-measured immediately before it is painted.
class _MaskedView {
  final RenderBox ro;
  final ElementData data;
  const _MaskedView({required this.ro, required this.data});
}

/// A revealed platform view. [data] carries the view's own bounds, which the
/// native side uses to find and crop it; [visibleRect] is the part an ancestor
/// clip leaves on screen, which is all we are allowed to paint.
class _CapturedView {
  final ElementData data;
  final Rect visibleRect;
  const _CapturedView({required this.data, required this.visibleRect});
}

class _PlatformViewRects {
  final List<_MaskedView> masked;
  final List<_CapturedView> captured;

  /// The screenshot container the rects are relative to, kept for re-measuring.
  final RenderObject? ancestor;

  const _PlatformViewRects({
    required this.masked,
    required this.captured,
    required this.ancestor,
  });
}

class ScreenshotCapturer {
  final PostHogConfig _config;

  /// Called when a capture tick reads a session id different from the one it
  /// last tracked, i.e. the native SDK rotated the session behind Dart's back.
  final VoidCallback? onSessionRotated;

  final ImageMaskPainter _imageMaskPainter = ImageMaskPainter();
  final _nativeCommunicator = NativeCommunicator();
  final _snapshotManager = SnapshotManager();

  bool _cancelled = false;

  bool hasCapturedPlatformViews = false;

  // Bumped whenever the per-session state is dropped. Frames name a session,
  // but a frame built before the first state read names none, and so does one
  // built right after a forced reset — the generation is what tells those two
  // apart.
  int _sessionGeneration = 0;

  // Held so confirmDelivered/onOcclusionEnded act on the exact status a frame
  // was built against, avoiding a containerKey re-lookup that can transiently fail.
  int? _lastTargetViewId;
  ViewTreeSnapshotStatus? _lastTargetStatus;

  // Dedup hashes of the latest capture, held until the sender confirms delivery.
  // Committing at capture time would poison dedup against a dropped frame,
  // freezing the replay until the pixels next change.
  int? _pendingImageBytesHash;
  int? _pendingCompositedBytesHash;

  /// The replay session the tracked snapshot state belongs to, read from native
  /// on every capture tick. Null until the first read, and after a forced reset.
  String? _replaySessionId;

  @visibleForTesting
  ViewTreeSnapshotStatus? get debugLastTargetStatus => _lastTargetStatus;

  @visibleForTesting
  String? get debugReplaySessionId => _replaySessionId;

  ScreenshotCapturer(this._config, {this.onSessionRotated});

  /// Resolves the live config at read time so masking flags never trail a
  /// close()/setup() reconfigure.
  @visibleForTesting
  PostHogConfig get effectiveConfig => Posthog().config ?? _config;

  void cancel() {
    _cancelled = true;
  }

  /// Drops all per-session snapshot state when [currentSessionId] differs from
  /// the session that state was built under: the new session needs its own meta
  /// event, and its first frame must not be deduped against the previous
  /// session's pixels.
  ///
  /// [force] resets even when the id is unchanged, for a restart the platform
  /// performs without rotating. The new id is unknown then, so it is left null
  /// until the next tick reads it.
  void resetSessionStateIfNeeded(
    String? currentSessionId, {
    bool force = false,
  }) {
    if (!force && _replaySessionId == currentSessionId) {
      return;
    }
    // Adopting an id for the first time is the same generation: an occlusion
    // placeholder built before any state read belongs to the session that read
    // then names, and must survive it. Every other reset starts a new one.
    if (force || _replaySessionId != null) {
      _sessionGeneration++;
    }
    _replaySessionId = currentSessionId;
    _snapshotManager.clear();
    _lastTargetViewId = null;
    _lastTargetStatus = null;
    _pendingImageBytesHash = null;
    _pendingCompositedBytesHash = null;
  }

  /// Whether [imageInfo] still belongs to the session the capturer is tracking
  /// — the session-level counterpart of the occlusion episode check. A frame
  /// outliving its session would land in the new session ahead of that
  /// session's meta event.
  ///
  /// It catches a forced reset landing mid-send, and a rotation adopted by a
  /// capture tick that was already in flight when an occlusion placeholder was
  /// built — that path is not serialized against tick captures. It does not
  /// catch a rotation observed by the same tick that produced the frame: that
  /// tick writes the tracked id before building it.
  ///
  /// The id alone cannot judge a frame naming no session, and there are two of
  /// those: an occlusion placeholder built before any state read, and anything
  /// built after a forced reset, which leaves the tracked id null until the
  /// next read. Hence the generation — the first must survive the read that
  /// names its session (dropping it would leave the episode showing the
  /// uncovered Flutter tree instead of the cover), the second must not survive
  /// the reset that ended its recording.
  bool sessionStillCurrent(ImageInfo imageInfo) =>
      imageInfo.generation == _sessionGeneration &&
      (imageInfo.sessionId == null || _replaySessionId == imageInfo.sessionId);

  /// Called when an occlusion episode ends: invalidates the dedup hashes (else
  /// the first Flutter frame matches the placeholder/bridged hash and freezes
  /// the replay) and re-arms meta (the bridge sent the native screen's meta).
  /// Uses the held status so it can't no-op on a transient lookup failure.
  void onOcclusionEnded() {
    final statusView = _lastTargetStatus;
    if (statusView == null) {
      return;
    }
    statusView.imageBytesHash = null;
    statusView.compositedBytesHash = null;
    statusView.sentMetaEvent = false;
  }

  /// Commits delivery state for [viewId]: the pending dedup hashes, and the meta
  /// latch when [metaSent]. Only the sender calls this, after actual delivery —
  /// capture paths must not self-commit, or a dropped frame poisons dedup and
  /// swallows the meta. An id mismatch means the RepaintBoundary was recreated.
  void confirmDelivered(int viewId, {required bool metaSent}) {
    if (viewId != _lastTargetViewId) {
      return;
    }
    final statusView = _lastTargetStatus;
    if (statusView == null) {
      return;
    }
    if (_pendingImageBytesHash != null) {
      statusView.imageBytesHash = _pendingImageBytesHash;
    }
    if (_pendingCompositedBytesHash != null) {
      statusView.compositedBytesHash = _pendingCompositedBytesHash;
    }
    if (metaSent) {
      statusView.sentMetaEvent = true;
    }
  }

  double _getPixelRatio({
    int? width,
    int? height,
    required double srcWidth,
    required double srcHeight,
  }) {
    if (width == null || height == null || srcWidth <= 0 || srcHeight <= 0) {
      return 1.0;
    }
    return min(width / srcWidth, height / srcHeight);
  }

  Future<Uint8List?> _getImageBytes(
    ui.Image img, {
    ui.ImageByteFormat format = ui.ImageByteFormat.png,
  }) async {
    try {
      final ByteData? byteData = await img.toByteData(format: format);
      if (byteData == null || byteData.lengthInBytes == 0) {
        printIfDebug('Error: Failed to convert image to byte data.');
        return null;
      }
      return byteData.buffer.asUint8List();
    } catch (e) {
      printIfDebug('Error converting image to byte data: $e');
      return null;
    }
  }

  bool _isPlatformViewRenderObject(RenderObject ro) =>
      ro is PlatformViewRenderBox ||
      ro is RenderDarwinPlatformView ||
      ro is TextureBox;

  _PlatformViewRects _collectPlatformViewRects(
      PostHogPlatformViewPrivacy defaultPolicy) {
    final masked = <_MaskedView>[];
    final captured = <_CapturedView>[];
    final ancestor = PostHogMaskController.instance.containerKey.currentContext
        ?.findRenderObject();
    final seen = <int>{};

    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement != null) {
      _visitElementForPlatformViews(
          rootElement, ancestor, masked, captured, seen, defaultPolicy);
    }

    if (masked.isNotEmpty || captured.isNotEmpty) {
      printIfDebug(
          'Found ${masked.length} masked and ${captured.length} captured platform view rect(s)');
    }
    return _PlatformViewRects(
        masked: masked, captured: captured, ancestor: ancestor);
  }

  void _visitElementForPlatformViews(
    Element element,
    RenderObject? ancestor,
    List<_MaskedView> masked,
    List<_CapturedView> captured,
    Set<int> seen,
    PostHogPlatformViewPrivacy inheritedPolicy,
  ) {
    final policy = resolvePrivacyPolicyForElement(element, inheritedPolicy);

    final ro = element.renderObject;
    if (ro is RenderBox &&
        ro.hasSize &&
        ro.size.isValidSize &&
        _isPlatformViewRenderObject(ro)) {
      _addIfNew(ro, ancestor, masked, captured, seen, policy);
    }
    element.visitChildren(
      (child) => _visitElementForPlatformViews(
          child, ancestor, masked, captured, seen, policy),
    );
  }

  void _addIfNew(
    RenderBox ro,
    RenderObject? ancestor,
    List<_MaskedView> masked,
    List<_CapturedView> captured,
    Set<int> seen,
    PostHogPlatformViewPrivacy policy,
  ) {
    if (!seen.add(identityHashCode(ro))) return;
    // TextureBox content is already composited into the Flutter image, so no
    // native screenshot is needed when revealing. Only mask it when requested.
    if (ro is TextureBox && policy == PostHogPlatformViewPrivacy.capture) {
      return;
    }
    try {
      final transform = ro.getTransformTo(ancestor);
      final visible = clippedPaintBounds(ro, ancestor);
      // A view an ancestor clips away entirely covers nothing on screen.
      if (visible.isEmpty) return;
      if (policy == PostHogPlatformViewPrivacy.capture) {
        captured.add(_CapturedView(
          data: ElementData(
            rect: ro.paintBounds,
            type: 'platformView',
            transform: transform,
          ),
          visibleRect: visible,
        ));
      } else {
        masked.add(_MaskedView(
          ro: ro,
          data: ElementData(
            rect: visible,
            type: 'platformView',
            transform: transform,
          ),
        ));
      }
    } catch (e) {
      printIfDebug('Error collecting platform view rect: $e');
    }
  }

  Map<String, int> _viewSpec(ElementData viewRect, Offset globalPosition) {
    final transform = viewRect.transform;
    if (transform == null) return {'x': 0, 'y': 0, 'width': 0, 'height': 0};
    final rect = MatrixUtils.transformRect(transform, viewRect.rect);
    return {
      'x': (globalPosition.dx + rect.left).round(),
      'y': (globalPosition.dy + rect.top).round(),
      'width': rect.width.round(),
      'height': rect.height.round(),
    };
  }

  /// Re-measures [view] and widens its mask to cover both where the view was
  /// when the rect was collected and where it is now.
  ///
  /// Clipping the mask to the visible region makes it tight enough to expose
  /// content whenever the tree moves between collection and this paint — the
  /// oversized rect used to hide that slop. Covering both positions fails
  /// closed; when nothing moved the two rects are equal and this is a no-op.
  ElementData _maskCoveringMotion(_MaskedView view, RenderObject? ancestor) {
    final collected = view.data;
    final collectedTransform = collected.transform;
    if (collectedTransform == null) return collected;
    try {
      if (!view.ro.attached || !view.ro.hasSize) return collected;
      final fresh = clippedPaintBounds(view.ro, ancestor);
      if (fresh.isEmpty) return collected;
      return ElementData(
        rect: maskRectCoveringMotion(collected.rect, collectedTransform, fresh,
            view.ro.getTransformTo(ancestor)),
        type: collected.type,
        transform: collectedTransform,
      );
    } catch (e) {
      printIfDebug('Error re-measuring a masked platform view: $e');
      return collected;
    }
  }

  Future<void> _compositeRevealedView(
    Canvas canvas,
    _CapturedView view,
    Uint8List? bytes,
    int nativeW,
    int nativeH,
    double pixelRatio,
  ) async {
    final viewRect = view.data;
    final transform = viewRect.transform;
    if (transform == null) return;
    final transformedRect = MatrixUtils.transformRect(transform, viewRect.rect);
    if (bytes == null) {
      _imageMaskPainter.drawMaskedImage(canvas, [viewRect], pixelRatio);
      return;
    }
    final nativeImage = await _decodeRawPixels(bytes, nativeW, nativeH);
    if (nativeImage == null) {
      _imageMaskPainter.drawMaskedImage(canvas, [viewRect], pixelRatio);
      return;
    }
    // The native request covers the view's own frame, because that is what the
    // platform matches it by. Clipping here, rather than shrinking the request,
    // keeps the revealed pixels inside the ancestor clip without changing what
    // the native side is asked for.
    canvas.save();
    canvas.clipRect(MatrixUtils.transformRect(transform, view.visibleRect));
    canvas.drawImageRect(
      nativeImage,
      Rect.fromLTWH(
          0, 0, nativeImage.width.toDouble(), nativeImage.height.toDouble()),
      transformedRect,
      Paint()..blendMode = ui.BlendMode.srcOver,
    );
    canvas.restore();
    nativeImage.dispose();
  }

  Future<ui.Image?> _decodeRawPixels(Uint8List bytes, int width, int height) {
    if (width <= 0 || height <= 0 || bytes.isEmpty) return Future.value(null);
    final completer = Completer<ui.Image?>();
    try {
      ui.decodeImageFromPixels(
        bytes,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );
    } catch (e) {
      printIfDebug('Error decoding raw pixels: $e');
      completer.complete(null);
    }
    return completer.future;
  }

  /// Computes a hash of the full raw RGBA byte array for change detection.
  /// This avoids retaining the full image bytes while still hashing every byte.
  int _computeImageHash(Uint8List bytes) {
    var hash = 0x811c9dc5; // FNV offset basis (32-bit)
    final length = bytes.length;

    // Always include the length in the hash.
    hash ^= length;
    hash = (hash * 0x01000193) & 0x7fffffff;

    if (bytes.offsetInBytes % 4 == 0) {
      final wordCount = length ~/ 4;
      final words =
          Uint32List.view(bytes.buffer, bytes.offsetInBytes, wordCount);
      for (var i = 0; i < wordCount; i++) {
        hash ^= words[i];
        hash = (hash * 0x01000193) & 0x7fffffff;
      }
      for (var i = wordCount * 4; i < length; i++) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0x7fffffff;
      }
    } else {
      for (var i = 0; i < length; i++) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0x7fffffff;
      }
    }

    return hash;
  }

  /// Shared prologue of [captureScreenshot]/[buildOcclusionPlaceholder]: resolves
  /// the container render object and per-view status, and resets [_cancelled] so a
  /// prior stop's cancel() can't veto a fresh capture. Null when not ready.
  ({
    RenderRepaintBoundary renderObject,
    ViewTreeSnapshotStatus statusView,
    bool shouldSendMetaEvent,
    Offset globalPosition,
  })? _resolveCaptureTarget() {
    _cancelled = false;

    final context = PostHogMaskController.instance.containerKey.currentContext;
    final renderObject = context?.findRenderObject() as RenderRepaintBoundary?;
    if (renderObject == null ||
        !renderObject.hasSize ||
        !renderObject.size.isValidSize) {
      return null;
    }

    final statusView = _snapshotManager.getStatus(renderObject);
    _lastTargetViewId = identityHashCode(renderObject);
    _lastTargetStatus = statusView;
    // A new capture owns the pending slots; a dropped predecessor's hashes
    // must not commit on this frame's delivery.
    _pendingImageBytesHash = null;
    _pendingCompositedBytesHash = null;
    return (
      renderObject: renderObject,
      statusView: statusView,
      shouldSendMetaEvent: !statusView.sentMetaEvent,
      globalPosition: renderObject.localToGlobal(Offset.zero),
    );
  }

  /// Builds one black placeholder frame for an occlusion episode, shown when a
  /// bridged capture can't be produced. Null when the view is not ready or
  /// rendering fails — like [captureScreenshot], it never throws.
  Future<ImageInfo?> buildOcclusionPlaceholder() async {
    try {
      return await _buildOcclusionPlaceholder();
    } catch (error) {
      printIfDebug('Error building occlusion placeholder: $error');
      return null;
    }
  }

  Future<ImageInfo?> _buildOcclusionPlaceholder() async {
    final target = _resolveCaptureTarget();
    if (target == null) {
      return null;
    }
    // Read before the awaits below, so a rotation or a forced reset mid-build
    // is visible to the sender as a stale frame.
    final sessionId = _replaySessionId;
    final generation = _sessionGeneration;
    final renderObject = target.renderObject;
    // Always with meta: a bridged episode already shipped the native screen's
    // meta, so without re-sending, the placeholder renders against its viewport.
    const shouldSendMetaEvent = true;
    final globalPosition = target.globalPosition;
    final srcWidth = renderObject.size.width;
    final srcHeight = renderObject.size.height;
    final width = srcWidth.toInt();
    final height = srcHeight.toInt();

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, srcWidth, srcHeight),
      Paint()..color = const Color(0xFF000000),
    );
    final picture = recorder.endRecording();

    ui.Image placeholderImage;
    try {
      placeholderImage = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }

    if (_cancelled || !placeholderImage.isValidSize) {
      placeholderImage.dispose();
      return null;
    }

    Uint8List? pngBytes;
    try {
      pngBytes = await _getImageBytes(placeholderImage);
    } finally {
      placeholderImage.dispose();
    }

    if (_cancelled || pngBytes == null || pngBytes.isEmpty) {
      return null;
    }

    // No status update here — the sender commits via [confirmDelivered].
    return ImageInfo(
      identityHashCode(renderObject),
      globalPosition.dx.toInt(),
      globalPosition.dy.toInt(),
      width,
      height,
      shouldSendMetaEvent,
      pngBytes,
      sessionId: sessionId,
      generation: generation,
    );
  }

  /// Captures one Flutter frame, or null when there is nothing to send. Never
  /// throws.
  Future<ImageInfo?> captureScreenshot() async {
    // Cleared again in _resolveCaptureTarget, but that runs after the round trip
    // below — whose post-await check would veto this capture on a prior flag.
    _cancelled = false;
    final state = await _nativeCommunicator.getSessionReplayState();
    if (_cancelled) {
      return null;
    }
    if (!state.isActive) {
      _snapshotManager.clear();
      return null;
    }
    final previousSessionId = _replaySessionId;
    // Before the capture target reads the meta latch below: a rotated session
    // must not inherit the previous session's latch or dedup hashes.
    resetSessionStateIfNeeded(state.sessionId);
    // Adopting an id for the first time (startup, or after a forced reset that
    // already asked for a sample) is not a rotation.
    if (previousSessionId != null && state.sessionId != previousSessionId) {
      onSessionRotated?.call();
    }
    return _captureScreenshot(state.sessionId, _sessionGeneration);
  }

  Future<ImageInfo?> _captureScreenshot(String? sessionId, int generation) {
    final target = _resolveCaptureTarget();
    if (target == null) {
      return Future.value(null);
    }
    final renderObject = target.renderObject;
    final statusView = target.statusView;
    final shouldSendMetaEvent = target.shouldSendMetaEvent;
    final globalPosition = target.globalPosition;

    final viewId = identityHashCode(renderObject);

    final Completer<ImageInfo?> completer = Completer<ImageInfo?>();

    try {
      final srcWidth = renderObject.size.width;
      final srcHeight = renderObject.size.height;
      final pixelRatio = _getPixelRatio(
        srcWidth: srcWidth,
        srcHeight: srcHeight,
      );

      final replayConfig = effectiveConfig.sessionReplayConfig;
      final maskAllContent =
          replayConfig.maskAllTexts || replayConfig.maskAllImages;

      ui.Image? image;
      ui.PictureRecorder? recorder;
      ui.Picture? picture;
      ui.Image? finalImage;

      Future(() async {
        // wait the UI to settle
        await SchedulerBinding.instance.endOfFrame;

        // Walk the tree for mask rects here, with no await before toImage(),
        // so the rects and the pixels come from the same frame. A walk done
        // before the async body freezes frame N's positions and paints them
        // onto frame N+k, which leaks content when the UI moves.
        final maskElements = PostHogMaskController.instance.getMaskElements(
          includeAllWidgets: maskAllContent,
        );
        // Fail closed: a failed walk must drop the frame, never ship an
        // unmasked screenshot.
        if (maskElements == null) {
          printIfDebug(
            'The widget mask walk failed, dropping the frame.',
          );
          completer.complete(null);
          return;
        }

        image = await renderObject.toImage(pixelRatio: pixelRatio);

        final currentImage = image;
        if (_cancelled) {
          currentImage?.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        if (currentImage == null || !currentImage.isValidSize) {
          _snapshotManager.clear();
          currentImage?.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        recorder = ui.PictureRecorder();
        final currentRecorder = recorder;
        if (currentRecorder == null) {
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }
        final canvas = Canvas(currentRecorder);

        Uint8List? imageBytes = await _getImageBytes(
          currentImage,
          format: ui.ImageByteFormat.rawRgba,
        );
        if (_cancelled) {
          currentRecorder.endRecording().dispose();
          recorder = null;
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        if (imageBytes == null || imageBytes.isEmpty) {
          printIfDebug(
            'Error: Failed to convert image byte data to Uint8List.',
          );
          currentRecorder.endRecording().dispose();
          recorder = null;
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        final preMaskHash = _computeImageHash(imageBytes);
        imageBytes = null;

        final defaultPolicy = replayConfig.maskAllPlatformViews
            ? PostHogPlatformViewPrivacy.mask
            : PostHogPlatformViewPrivacy.capture;
        final pvRects = _collectPlatformViewRects(defaultPolicy);
        final hasCapturedViews = pvRects.captured.isNotEmpty;
        hasCapturedPlatformViews = hasCapturedViews;

        if (!hasCapturedViews && preMaskHash == statusView.imageBytesHash) {
          printIfDebug(
            'Snapshot is the same as the last one, nothing changed, do nothing.',
          );
          currentRecorder.endRecording().dispose();
          recorder = null;
          currentImage.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        try {
          canvas.drawImage(currentImage, Offset.zero, Paint());
        } finally {
          currentImage.dispose();
          image = null;
        }

        if (_cancelled) {
          currentRecorder.endRecording().dispose();
          recorder = null;
          completer.complete(null);
          return;
        }

        if (maskElements.isNotEmpty) {
          _imageMaskPainter.drawMaskedImage(
            canvas,
            maskElements,
            pixelRatio,
          );
        }

        if (pvRects.masked.isNotEmpty) {
          _imageMaskPainter.drawMaskedImage(
            canvas,
            pvRects.masked
                .map((m) => _maskCoveringMotion(m, pvRects.ancestor))
                .toList(),
            pixelRatio,
          );
        }
        if (pvRects.captured.isNotEmpty) {
          final specs = pvRects.captured
              .map((v) => _viewSpec(v.data, globalPosition))
              .toList();
          final bytesList =
              await _nativeCommunicator.captureNativeScreenshots(specs);
          if (_cancelled) {
            currentRecorder.endRecording().dispose();
            recorder = null;
            completer.complete(null);
            return;
          }
          for (var i = 0; i < pvRects.captured.length; i++) {
            final spec = specs[i];
            final bytes = i < bytesList.length ? bytesList[i] : null;
            await _compositeRevealedView(canvas, pvRects.captured[i], bytes,
                spec['width']!, spec['height']!, pixelRatio);
          }
        }

        picture = currentRecorder.endRecording();
        recorder = null;

        final currentPicture = picture;
        if (currentPicture == null) {
          completer.complete(null);
          return;
        }

        try {
          finalImage = await currentPicture.toImage(
            srcWidth.toInt(),
            srcHeight.toInt(),
          );

          final currentFinalImage = finalImage;
          if (_cancelled) {
            currentFinalImage?.dispose();
            finalImage = null;
            completer.complete(null);
            return;
          }

          if (currentFinalImage == null || !currentFinalImage.isValidSize) {
            currentFinalImage?.dispose();
            finalImage = null;
            completer.complete(null);
            return;
          }

          try {
            _pendingImageBytesHash = preMaskHash;

            final pngBytes = await _getImageBytes(currentFinalImage);
            if (_cancelled || pngBytes == null || pngBytes.isEmpty) {
              completer.complete(null);
              return;
            }

            if (hasCapturedViews) {
              final compositedHash = _computeImageHash(pngBytes);
              if (compositedHash == statusView.compositedBytesHash) {
                printIfDebug(
                  'Composited snapshot is the same as the last one, nothing changed, do nothing.',
                );
                completer.complete(null);
                return;
              }
              _pendingCompositedBytesHash = compositedHash;
            }

            final imageInfo = ImageInfo(
              viewId,
              globalPosition.dx.toInt(),
              globalPosition.dy.toInt(),
              srcWidth.toInt(),
              srcHeight.toInt(),
              shouldSendMetaEvent,
              pngBytes,
              sessionId: sessionId,
              generation: generation,
            );
            // No status commit here: the sender may still drop this frame, and
            // committing for a never-sent frame breaks playback / freezes dedup.
            // The sender commits via [confirmDelivered] after delivery.
            completer.complete(imageInfo);
          } finally {
            currentFinalImage.dispose();
            finalImage = null;
          }
        } finally {
          currentPicture.dispose();
          picture = null;
        }
      }).catchError((error) {
        finalImage?.dispose();
        finalImage = null;
        picture?.dispose();
        picture = null;
        final currentRecorder = recorder;
        if (currentRecorder != null) {
          currentRecorder.endRecording().dispose();
          recorder = null;
        }
        image?.dispose();
        image = null;

        printIfDebug('Error capturing image: $error');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      return completer.future;
    } catch (e) {
      printIfDebug('Error initializing capture: $e');
      return Future.value(null);
    }
  }
}

/// Intersects [ro]'s paint bounds with every clip its ancestors apply, up to
/// but not including [ancestor], and returns the visible rect in [ro]'s local
/// coordinates.
///
/// A platform view reports its full, unclipped paint bounds, so a map inside a
/// scroll view or a `ClipRect` would otherwise be masked past its visible edge
/// and over the widgets below it. Returns [Rect.zero] when the view is fully
/// clipped away.
@visibleForTesting
Rect clippedPaintBounds(RenderBox ro, RenderObject? ancestor) {
  var clipped = ro.paintBounds;
  RenderObject child = ro;
  RenderObject? node = ro.parent;
  while (node != null && !identical(node, ancestor)) {
    final clip = node.describeApproximatePaintClip(child);
    if (clip != null) {
      // The clip is in node's coordinates; map it into ro's frame.
      final toRo = Matrix4.tryInvert(ro.getTransformTo(node));
      if (toRo != null) {
        clipped = clipped.intersect(MatrixUtils.transformRect(toRo, clip));
        if (clipped.isEmpty) return Rect.zero;
      }
    }
    child = node;
    node = node.parent;
  }
  return clipped;
}

/// The rect to mask, widened to cover a view at both the position it was
/// collected at and the position it now occupies. See [_maskCoveringMotion].
@visibleForTesting
Rect maskRectCoveringMotion(
  Rect collectedRect,
  Matrix4 collectedTransform,
  Rect freshRect,
  Matrix4 freshTransform,
) {
  final inverse = Matrix4.tryInvert(collectedTransform);
  if (inverse == null) return collectedRect;
  return collectedRect.expandToInclude(MatrixUtils.transformRect(
    inverse.multiplied(freshTransform),
    freshRect,
  ));
}

@visibleForTesting
PostHogPlatformViewPrivacy resolvePrivacyPolicyForElement(
  Element element,
  PostHogPlatformViewPrivacy inherited,
) {
  if (element.widget is PostHogPlatformView) {
    return (element.widget as PostHogPlatformView).privacy;
  }
  return inherited;
}
