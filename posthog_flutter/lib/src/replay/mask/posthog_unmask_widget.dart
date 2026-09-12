import 'package:flutter/widgets.dart';

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
/// On Flutter web, canvas masking must already be enabled through
/// `session_recording.canvasCapture.maskRegionsFn` in `posthog.init`, or by
/// mounting a `PostHogMaskWidget`. This widget does not enable canvas recording
/// or masking itself. Keep it inside `PostHogWidget` on all platforms.
class PostHogUnmaskWidget extends StatelessWidget {
  /// The known-safe widget subtree to reveal in session replay.
  final Widget child;

  /// Creates an exception to global text/image masking around [child].
  const PostHogUnmaskWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
