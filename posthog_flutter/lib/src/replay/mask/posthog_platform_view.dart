import 'package:flutter/widgets.dart';

/// Controls how a platform view is handled in session replay.
enum PostHogPlatformViewPrivacy {
  /// Mask the view with a black rectangle (default).
  mask,

  /// Reveal the view content in session replay.
  ///
  /// On Android texture mode the content is already in the Flutter render base,
  /// so no extra capture work is done. On iOS and hybrid composition the
  /// compositor fills the transparent hole via a native capture + dstOver.
  capture,
}

/// Session replay policy marker for an embedded platform view.
///
/// Wrap a platform view (e.g. [WebViewWidget], [GoogleMap]) to override the
/// global [PostHogSessionReplayConfig.maskAllPlatformViews] setting for that
/// specific view.
///
/// ```dart
/// PostHogPlatformView(
///   privacy: PostHogPlatformViewPrivacy.capture,
///   child: WebViewWidget(controller: _controller),
/// )
/// ```
///
/// This widget has no runtime state — it is a pure marker. The compositor reads
/// [privacy] from the element tree during each capture frame.
class PostHogPlatformView extends StatelessWidget {
  final Widget child;
  final PostHogPlatformViewPrivacy privacy;

  const PostHogPlatformView({
    super.key,
    required this.child,
    this.privacy = PostHogPlatformViewPrivacy.mask,
  });

  @override
  Widget build(BuildContext context) => child;
}
