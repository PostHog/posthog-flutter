import 'package:flutter/widgets.dart';

import 'canvas_mask_registration_io.dart'
    if (dart.library.js_interop) 'canvas_mask_registration_web.dart';

/// Reveals a widget subtree in session replay despite global text/image masking.
///
/// Keep `maskAllTexts` / `maskAllImages` enabled and reveal only known-safe UI:
///
/// ```dart
/// PostHogUnmaskWidget(child: Text('Try again'))
/// ```
///
/// Only wrap content known to be safe. Explicit `PostHogMaskWidget` masks and
/// sensitive text inputs always take precedence, regardless of nesting order.
/// This does not erase masks from ancestors or overlapping widgets, reveal
/// native platform views, or change masking on captured native screens.
///
/// On Flutter web, mounting either this widget or `PostHogMaskWidget` enables
/// canvas masking and restarts an in-flight recording once to protect the
/// semantics DOM too. Canvas recording must be enabled separately. Frames
/// captured before the first mount are not protected by this opt-in. Declare
/// `session_recording: { canvasCapture: { maskRegionsFn: () => null } }` in
/// `posthog.init` to skip those frames until Flutter installs its mask provider.
/// Keep both kinds of wrapper inside `PostHogWidget` on all platforms. On web,
/// a mounted wrapper outside the tracked tree causes frames to be skipped once
/// masking is enabled, until it is moved inside or removed.
class PostHogUnmaskWidget extends StatefulWidget {
  /// The known-safe widget subtree to reveal in session replay.
  final Widget child;

  /// Creates an exception to global text/image masking around [child].
  const PostHogUnmaskWidget({super.key, required this.child});

  @override
  State<PostHogUnmaskWidget> createState() => _PostHogUnmaskWidgetState();
}

class _PostHogUnmaskWidgetState extends State<PostHogUnmaskWidget> {
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
  Widget build(BuildContext context) => widget.child;
}
