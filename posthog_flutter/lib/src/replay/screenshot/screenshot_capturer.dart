import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  ImageInfo(
    this.id,
    this.x,
    this.y,
    this.width,
    this.height,
    this.shouldSendMetaEvent,
    this.imageBytes,
  );
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

class _PlatformViewRects {
  final List<ElementData> masked;
  final List<ElementData> captured;
  const _PlatformViewRects({required this.masked, required this.captured});
}

class ScreenshotCapturer {
  final PostHogConfig _config;
  final ImageMaskPainter _imageMaskPainter = ImageMaskPainter();
  final _nativeCommunicator = NativeCommunicator();
  final _snapshotManager = SnapshotManager();

  bool _cancelled = false;

  bool hasCapturedPlatformViews = false;

  // Held so confirmDelivered/onOcclusionEnded act on the exact status a frame
  // was built against, avoiding a containerKey re-lookup that can transiently fail.
  int? _lastTargetViewId;
  ViewTreeSnapshotStatus? _lastTargetStatus;

  // Dedup hashes of the latest capture, held until the sender confirms delivery.
  // Committing at capture time would poison dedup against a dropped frame,
  // freezing the replay until the pixels next change.
  int? _pendingImageBytesHash;
  int? _pendingCompositedBytesHash;

  @visibleForTesting
  ViewTreeSnapshotStatus? get debugLastTargetStatus => _lastTargetStatus;

  ScreenshotCapturer(this._config);

  void cancel() {
    _cancelled = true;
  }

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
    final masked = <ElementData>[];
    final captured = <ElementData>[];
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
    return _PlatformViewRects(masked: masked, captured: captured);
  }

  void _visitElementForPlatformViews(
    Element element,
    RenderObject? ancestor,
    List<ElementData> masked,
    List<ElementData> captured,
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
    List<ElementData> masked,
    List<ElementData> captured,
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
      final data = ElementData(
        rect: ro.paintBounds,
        type: 'platformView',
        transform: transform,
      );
      if (policy == PostHogPlatformViewPrivacy.capture) {
        captured.add(data);
      } else {
        masked.add(data);
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

  Future<void> _compositeRevealedView(
    Canvas canvas,
    ElementData viewRect,
    Uint8List? bytes,
    int nativeW,
    int nativeH,
    double pixelRatio,
  ) async {
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
    canvas.drawImageRect(
      nativeImage,
      Rect.fromLTWH(
          0, 0, nativeImage.width.toDouble(), nativeImage.height.toDouble()),
      transformedRect,
      Paint()..blendMode = ui.BlendMode.srcOver,
    );
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
    );
  }

  Future<ImageInfo?> captureScreenshot() {
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

      final replayConfig = _config.sessionReplayConfig;

      final postHogWidgetWrapperElements =
          PostHogMaskController.instance.getPostHogWidgetWrapperElements();

      // call getCurrentScreenRects if really necessary
      List<ElementData>? elementsDataWidgets;
      if (replayConfig.maskAllTexts || replayConfig.maskAllImages) {
        elementsDataWidgets =
            PostHogMaskController.instance.getCurrentWidgetsElements();
      }

      ui.Image? image;
      ui.PictureRecorder? recorder;
      ui.Picture? picture;
      ui.Image? finalImage;

      Future(() async {
        final isSessionReplayActive =
            await _nativeCommunicator.isSessionReplayActive();
        if (_cancelled) {
          completer.complete(null);
          return;
        }
        if (!isSessionReplayActive) {
          _snapshotManager.clear();
          completer.complete(null);
          return;
        }

        // wait the UI to settle
        await SchedulerBinding.instance.endOfFrame;
        image = await renderObject.toImage(pixelRatio: pixelRatio);

        final currentImage = image;
        if (_cancelled) {
          currentImage?.dispose();
          image = null;
          completer.complete(null);
          return;
        }

        if (currentImage == null ||
            !isSessionReplayActive ||
            !currentImage.isValidSize) {
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

        if (replayConfig.maskAllTexts || replayConfig.maskAllImages) {
          if (elementsDataWidgets != null && elementsDataWidgets.isNotEmpty) {
            _imageMaskPainter.drawMaskedImage(
              canvas,
              elementsDataWidgets,
              pixelRatio,
            );
          }
        } else {
          if (postHogWidgetWrapperElements != null &&
              postHogWidgetWrapperElements.isNotEmpty) {
            _imageMaskPainter.drawMaskedImage(
              canvas,
              postHogWidgetWrapperElements,
              pixelRatio,
            );
          }
        }

        if (pvRects.masked.isNotEmpty) {
          _imageMaskPainter.drawMaskedImage(
            canvas,
            pvRects.masked,
            pixelRatio,
          );
        }
        if (pvRects.captured.isNotEmpty) {
          final specs = pvRects.captured
              .map((r) => _viewSpec(r, globalPosition))
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
