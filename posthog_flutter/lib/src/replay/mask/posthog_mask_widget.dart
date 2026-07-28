import 'package:flutter/material.dart';

/// Masks a widget subtree in PostHog session replay snapshots.
///
/// Wrap sensitive UI with [PostHogMaskWidget] to hide that area in captured
/// screenshots, regardless of the global session replay masking settings.
///
/// **Flutter web:** this has no effect unless canvas masking is enabled, since
/// the canvas is masked by posthog-js rather than by this plugin. Declare
/// `session_recording: { canvasCapture: { maskRegionsFn: () => null } }`
/// in your `posthog.init` call to turn it on. iOS and Android need no setup.
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
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(key: _widgetKey, child: widget.child);
  }
}
