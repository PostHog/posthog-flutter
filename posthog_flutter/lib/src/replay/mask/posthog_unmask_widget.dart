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
/// Only wrap content known to be safe. This overrides global masking and
/// `PostHogMaskWidget` in either nesting order, but sensitive text inputs always
/// remain masked. Masks on overlapping sibling widgets are not removed.
///
/// For an enclosing mask, only the visible rectangular unmask region is
/// excluded. If its transform relative to that mask is not axis-aligned, or a
/// non-rectangular/custom clip prevents a safe exclusion, the enclosing mask is
/// retained. Web masks use conservative bounds and can cover the edges of an
/// unmasked region. Native platform views and captured native screens are
/// unaffected.
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
