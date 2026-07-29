import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show View;
import 'package:web/web.dart' as web;

import '../../posthog_config.dart';
import '../../posthog_flutter_web_handler.dart';
import '../../util/logging.dart';
import '../mask/posthog_mask_controller.dart';
import 'web_canvas_mask_geometry.dart';

extension type _JSMaskRegion._(JSObject _) implements JSObject {
  external factory _JSMaskRegion({
    required double x,
    required double y,
    required double width,
    required double height,
  });
}

@JS('Object.assign')
external JSObject _objectAssign(JSObject target, JSObject source);

const _semanticsBlockSelector = 'flt-semantics-host';

// Placeholder that keeps the gate inert: must be pinned to the first
// posthog-js release containing canvasCapture.maskRegionsFn support
// (github.com/PostHog/posthog-js#4270) before this package releases.
const _minPosthogJsVersion = '0.0.0';

/// Supplies widget-tree mask rectangles to posthog-js canvas recording via
/// `session_recording.canvasCapture.maskRegionsFn`, so text painted
/// into the CanvasKit canvas can be masked even though DOM masking cannot
/// see it.
///
/// An app opts in by declaring `maskRegionsFn` in its `posthog.init`
/// call; declaring it as `() => null` also covers the frames captured before
/// this provider takes over. Without that key nothing is registered, so
/// recording is left exactly as posthog-js configured it.
///
/// Fails closed: a failed widget-tree walk returns null, which makes
/// posthog-js skip the frame instead of shipping it unmasked.
class WebCanvasMaskProvider {
  WebCanvasMaskProvider(this._config);

  static WebCanvasMaskProvider? _active;
  static bool _warnedOldPosthogJs = false;

  @visibleForTesting
  static String? debugMinPosthogJsVersionOverride;

  // the test harness runs full-page, where the real host is <body> and can
  // never be distinguished from a foreign view's host
  @visibleForTesting
  static web.Element? debugOwnViewHostOverride;

  @visibleForTesting
  static void resetForTesting() {
    _active?._retryTimer?.cancel();
    _active = null;
    _warnedOldPosthogJs = false;
    debugMinPosthogJsVersionOverride = null;
    debugOwnViewHostOverride = null;
  }

  final PostHogConfig _config;

  Timer? _retryTimer;
  List<Rect>? _cachedContainerRects;
  int _cachedAtFrame = -1;
  int _consecutiveWalkFailures = 0;
  bool _warnedWalkFailure = false;
  bool _pendingRestart = false;

  // shared so a second provider's cache is not compared against a counter that
  // never advances; the callback cannot be removed once added
  static int _frameCount = 0;
  static bool _frameCallbackRegistered = false;

  void register() {
    try {
      // a second setup() must not leave the predecessor's retry chain
      // polling — it would apply config captured from the old Posthog config
      _active?._retryTimer?.cancel();
      _active = this;
      // the controller singleton may predate this setup() and still hold a
      // parser map built from an older config's masking flags
      PostHogMaskController.instance
          .refreshParsers(_config.sessionReplayConfig);
      _registerUnsafe();
    } catch (e) {
      // a partial first apply (set_config landed, restart threw) must not end
      // the chain — the retry re-runs the whole apply, which is idempotent
      printIfDebug('PostHog: failed to register web canvas masking: $e');
      _scheduleRetry(const Duration(milliseconds: 250));
    }
  }

  void _registerUnsafe() {
    final ph = posthog;
    if (ph != null && _tryApplyConfig(ph)) {
      return;
    }
    // the posthog-js snippet installs a config-less stub and array.js later
    // REPLACES window.posthog with the real instance, so each retry must
    // re-read the getter; set_config against the stub would merge onto an
    // empty base and wipe the user's session_recording config
    printIfDebug(
      'PostHog: posthog-js not fully loaded yet, '
      'retrying canvas mask registration.',
    );
    _scheduleRetry(const Duration(milliseconds: 250));
  }

  // polls forever once backed off to 4s: a consent-gated app can call
  // posthog.init minutes after Flutter boots, and giving up would silently
  // leave its canvas frames skipped (maskRegionsFn stuck at () => null)
  void _scheduleRetry(Duration delay) {
    _retryTimer = Timer(delay, () {
      // ramped up front so a throwing apply backs off like the
      // posthog-not-ready path instead of retrying at a fixed 250ms forever
      final doubled = delay * 2;
      final next = doubled > const Duration(seconds: 4)
          ? const Duration(seconds: 4)
          : doubled;
      try {
        final current = posthog;
        if (current != null && _tryApplyConfig(current)) {
          return;
        }
      } catch (e) {
        printIfDebug('PostHog: web canvas masking retry failed: $e');
      }
      _scheduleRetry(next);
    });
  }

  void _ensureFrameCounter() {
    if (_frameCallbackRegistered) {
      return;
    }
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      _frameCount++;
    });
    _frameCallbackRegistered = true;
  }

  // posthog-js constructs its instance with a default config before init()
  // runs, so a present config does not mean the app has called init — a
  // consent-gated app may init long after Flutter boots. Only __loaded
  // (set when init completes) distinguishes the two.
  bool _isInitialized(PostHog ph) {
    if (ph.config == null) {
      return false;
    }
    final loaded = (ph as JSObject).getProperty<JSAny?>('__loaded'.toJS);
    return loaded.isA<JSBoolean>() && (loaded as JSBoolean).toDart;
  }

  bool _tryApplyConfig(PostHog ph) {
    if (!_isInitialized(ph)) {
      return false;
    }

    // shallow-merge on top of any user-provided session_recording config —
    // posthog-js set_config replaces the whole session_recording object
    final sessionRecording = JSObject();
    final existing = ph.config?.getProperty<JSAny?>('session_recording'.toJS);
    if (existing.isA<JSObject>()) {
      _objectAssign(sessionRecording, existing as JSObject);
    }

    final canvasCapture = JSObject();
    final existingCanvasCapture =
        sessionRecording.getProperty<JSAny?>('canvasCapture'.toJS);
    if (existingCanvasCapture.isA<JSObject>()) {
      _objectAssign(canvasCapture, existingCanvasCapture as JSObject);
    }
    // the app opts into canvas masking by declaring maskRegionsFn in
    // posthog.init — registering regardless would restart an in-flight
    // recording and drop the semantics tree for apps that never asked
    if (!canvasCapture.has('maskRegionsFn')) {
      _warnNotOptedIn(sessionRecording);
      return true;
    }
    _warnIfPosthogJsTooOld(ph);
    _ensureFrameCounter();
    canvasCapture.setProperty(
      'maskRegionsFn'.toJS,
      _computeMaskRegions.toJS,
    );
    sessionRecording.setProperty('canvasCapture'.toJS, canvasCapture);

    _blockSemanticsHost(sessionRecording);

    final config = JSObject();
    config.setProperty('session_recording'.toJS, sessionRecording);
    ph.set_config(config);

    // blockSelector is only read when rrweb's record() starts, so an in-flight
    // recording must be restarted. _pendingRestart survives a stop that
    // succeeded while the matching start threw: the retry sees the recording
    // as already stopped and must still finish the restart.
    if (ph.sessionRecordingStarted()) {
      _pendingRestart = true;
      ph.stopSessionRecording();
    }
    if (_pendingRestart) {
      ph.startSessionRecording();
      _pendingRestart = false;
    }
    return true;
  }

  // canvas recording can also be switched on from project settings, which the
  // plugin cannot read — so only the posthog.init half of the leak is warnable
  void _warnNotOptedIn(JSObject sessionRecording) {
    printIfDebug(
      'PostHog: maskRegionsFn is not declared in posthog.init, '
      'so Flutter web canvas masking is off.',
    );
    final replayConfig = _config.sessionReplayConfig;
    if (!replayConfig.maskAllTexts && !replayConfig.maskAllImages) {
      return;
    }
    final captureCanvas =
        sessionRecording.getProperty<JSAny?>('captureCanvas'.toJS);
    if (!captureCanvas.isA<JSObject>()) {
      return;
    }
    final recordCanvas =
        (captureCanvas as JSObject).getProperty<JSAny?>('recordCanvas'.toJS);
    if (recordCanvas.isA<JSBoolean>() && (recordCanvas as JSBoolean).toDart) {
      web.console.warn(
        'PostHog: canvas session recording is enabled but maskRegionsFn '
                'is missing from posthog.init, so text painted by Flutter is recorded '
                'unmasked. See the posthog_flutter CHANGELOG for the snippet.'
            .toJS,
      );
    }
  }

  // warns only on a version confirmed older than the minimum: an absent or
  // unparseable version (custom bundle, future scheme) is assumed new so the
  // gate can never misfire, and registration always proceeds — blockSelector
  // still protects the accessibility DOM on old posthog-js
  void _warnIfPosthogJsTooOld(PostHog ph) {
    if (_warnedOldPosthogJs) {
      return;
    }
    try {
      final min = debugMinPosthogJsVersionOverride ?? _minPosthogJsVersion;
      final raw = (ph as JSObject).getProperty<JSAny?>('version'.toJS);
      if (!raw.isA<JSString>()) {
        return;
      }
      final observed = (raw as JSString).toDart;
      if (!_isConfirmedOlder(observed, min)) {
        return;
      }
      _warnedOldPosthogJs = true;
      web.console.warn(
        'PostHog: this posthog-js version ($observed) does not support '
                'canvasCapture.maskRegionsFn, so canvas frames are NOT masked '
                '— upgrade to at least $min for canvas masking. The '
                'accessibility-DOM exclusion is still applied.'
            .toJS,
      );
    } catch (e) {
      printIfDebug('PostHog: could not check the posthog-js version: $e');
    }
  }

  static bool _isConfirmedOlder(String observed, String min) {
    final observedParts = _parseSemVerPrefix(observed);
    final minParts = _parseSemVerPrefix(min);
    if (observedParts == null || minParts == null) {
      return false;
    }
    for (var i = 0; i < 3; i++) {
      if (observedParts[i] != minParts[i]) {
        return observedParts[i] < minParts[i];
      }
    }
    return false;
  }

  static List<int>? _parseSemVerPrefix(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
    if (match == null) {
      return null;
    }
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  // with accessibility enabled, Flutter mirrors widget text into the
  // flt-semantics DOM tree, which rrweb would otherwise record in plaintext
  void _blockSemanticsHost(JSObject sessionRecording) {
    final existing = sessionRecording.getProperty<JSAny?>('blockSelector'.toJS);
    var selector = _semanticsBlockSelector;
    if (existing.isA<JSString>()) {
      final current = (existing as JSString).toDart;
      // token-exact: a user selector like `.not-flt-semantics-host` must not
      // pass for the semantics-host selector itself
      final alreadyBlocked = current
          .split(',')
          .map((token) => token.trim())
          .contains(_semanticsBlockSelector);
      if (alreadyBlocked) {
        return;
      }
      selector = '$current, $_semanticsBlockSelector';
    }
    sessionRecording.setProperty('blockSelector'.toJS, selector.toJS);
  }

  // null tells posthog-js to skip the frame rather than ship it unmasked
  JSArray<JSObject>? _computeMaskRegions(web.HTMLCanvasElement canvas) {
    try {
      return _unsafeComputeMaskRegions(canvas);
    } catch (e) {
      printIfDebug('PostHog: error computing canvas mask regions: $e');
      return null;
    }
  }

  JSArray<JSObject>? _unsafeComputeMaskRegions(web.HTMLCanvasElement canvas) {
    final host = _flutterViewHost(canvas);
    if (host == null) {
      return JSArray<JSObject>();
    }

    final containerRects = _currentContainerRects();
    if (containerRects == null) {
      _noteWalkFailure();
      return null;
    }
    _consecutiveWalkFailures = 0;

    // our rects always describe PostHogWidget's tree — shipping them with a
    // different flutter-view's canvas would record that view unmasked
    if (!_isOwnViewCanvas(host)) {
      return null;
    }
    if (containerRects.isEmpty) {
      return JSArray<JSObject>();
    }

    // rects are container-local, so map them through the container's full
    // transform (an ancestor Transform.scale scales painted content, and a
    // plain origin shift would leave the masks at the unscaled size); the
    // hostRect term covers a flutter-view embedded away from the viewport
    // origin, since Flutter logical pixels == CSS pixels on web
    Matrix4? containerTransform;
    final containerObject = PostHogMaskController
        .instance.containerKey.currentContext
        ?.findRenderObject();
    if (containerObject is RenderBox && containerObject.hasSize) {
      containerTransform = containerObject.getTransformTo(null);
    }
    final canvasRect = canvas.getBoundingClientRect();
    final hostRect = host.getBoundingClientRect();
    final offset = Offset(
      hostRect.left - canvasRect.left,
      hostRect.top - canvasRect.top,
    );

    final regions = <JSObject>[];
    for (final rect in containerRects) {
      final globalRect = containerTransform == null
          ? rect
          : MatrixUtils.transformRect(containerTransform, rect);
      final shifted = globalRect.shift(offset);
      regions.add(_JSMaskRegion(
        x: shifted.left,
        y: shifted.top,
        width: shifted.width,
        height: shifted.height,
      ));
    }
    return regions.toJS;
  }

  // In full-page mode the embedder host is <body>, which contains every
  // flutter-view on the page, so only a view embedded in a dedicated host
  // element (multi-view) can be told apart from ours.
  bool _isOwnViewCanvas(web.Element canvasViewHost) {
    final ownHost = debugOwnViewHostOverride ?? _resolveOwnViewHost();
    if (ownHost != null) {
      return ownHost.contains(canvasViewHost);
    }
    // unresolvable: with a single flutter-view it can only be ours
    return web.document.querySelectorAll('flutter-view').length <= 1;
  }

  web.Element? _resolveOwnViewHost() {
    try {
      final context =
          PostHogMaskController.instance.containerKey.currentContext;
      if (context == null) {
        return null;
      }
      final viewId = View.maybeOf(context)?.viewId;
      if (viewId == null) {
        return null;
      }
      final hostElement = ui_web.views.getHostElement(viewId);
      if (hostElement != null && hostElement.isA<web.Element>()) {
        return hostElement as web.Element;
      }
    } catch (e) {
      printIfDebug('PostHog: could not resolve the Flutter view host: $e');
    }
    return null;
  }

  // rects only change when Flutter paints a frame, so cache per frame instead
  // of recomputing on every posthog-js canvas tick
  List<Rect>? _currentContainerRects() {
    if (_cachedContainerRects != null && _cachedAtFrame == _frameCount) {
      return _cachedContainerRects;
    }

    final replayConfig = _config.sessionReplayConfig;
    final elements = PostHogMaskController.instance.getMaskElements(
      includeAllWidgets:
          replayConfig.maskAllTexts || replayConfig.maskAllImages,
    );
    if (elements == null) {
      _cachedContainerRects = null;
      return null;
    }

    final rects = containerMaskRects(elements);
    _cachedContainerRects = rects;
    _cachedAtFrame = _frameCount;
    return rects;
  }

  // PostHogWidget can mount a moment after recording starts, so a few
  // fail-closed frames during boot are normal; only a persistent failure
  // means the canvas is never recorded
  void _noteWalkFailure() {
    if (_warnedWalkFailure) {
      return;
    }
    _consecutiveWalkFailures++;
    if (_consecutiveWalkFailures >= 10) {
      _warnedWalkFailure = true;
      web.console.warn(
        'PostHog: session replay masking cannot find the PostHogWidget '
                'widget tree, so canvas frames are not being recorded. '
                'Wrap your app in PostHogWidget, or remove maskRegionsFn '
                'from your posthog.init to disable canvas masking (the canvas '
                'is then recorded unmasked).'
            .toJS,
      );
    }
  }

  web.Element? _flutterViewHost(web.HTMLCanvasElement canvas) {
    final root = canvas.getRootNode();
    final web.Element start =
        root.isA<web.ShadowRoot>() ? (root as web.ShadowRoot).host : canvas;
    return start.closest('flutter-view');
  }
}
