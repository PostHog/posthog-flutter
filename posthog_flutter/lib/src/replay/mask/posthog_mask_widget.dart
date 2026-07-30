import 'package:flutter/material.dart';

import 'canvas_mask_registration_io.dart'
    if (dart.library.js_interop) 'canvas_mask_registration_web.dart';

/// Masks a widget subtree in PostHog session replay snapshots.
///
/// Wrap sensitive UI with [PostHogMaskWidget] to hide that area in captured
/// screenshots, regardless of the global session replay masking settings.
///
/// **Flutter web:** the canvas is masked by posthog-js rather than by this
/// plugin, so the first [PostHogMaskWidget] to mount turns canvas masking on —
/// which restarts an in-flight recording once, because masking also excludes
/// the Flutter semantics DOM tree via `blockSelector`, and posthog-js only
/// reads that when recording starts. Canvas recording itself must be enabled
/// separately — either with `captureCanvas: { recordCanvas: true }` as shown
/// below, or with the canvas capture toggle in your project's session replay
/// settings. Frames captured before that first mount are recorded unmasked;
/// to cover the window between `posthog.init` and Flutter booting, declare
/// `session_recording: { captureCanvas: { recordCanvas: true },
/// canvasCapture: { maskRegionsFn: () => null } }`
/// in your `posthog.init` call — until this plugin takes over, those frames are
/// skipped instead of recorded. Your app must be wrapped in `PostHogWidget`,
/// and every [PostHogMaskWidget] must sit inside it — otherwise canvas frames
/// are skipped instead of recorded unmasked, until the mask widget is moved
/// inside `PostHogWidget` or removed. iOS and Android need no setup either
/// way.
class PostHogMaskWidget extends StatefulWidget {
  /// The widget subtree to mask in session replay snapshots.
  final Widget child;

  /// Creates a mask around [child] for session replay.
  const PostHogMaskWidget({super.key, required this.child});

  @override
  PostHogMaskWidgetState createState() => PostHogMaskWidgetState();
}

/// State for [PostHogMaskWidget].
class PostHogMaskWidgetState extends State<PostHogMaskWidget> {
  final GlobalKey _widgetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    notifyMaskWidgetMounted(context);
  }

  @override
  void dispose() {
    notifyMaskWidgetUnmounted(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(key: _widgetKey, child: widget.child);
  }
}
