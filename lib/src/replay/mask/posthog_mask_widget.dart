import 'package:flutter/material.dart';

/// A widget that masks its child's content in session replay recordings.
///
/// Wrap any widget with [PostHogMaskWidget] to ensure its content is
/// hidden in session replays, useful for sensitive information that should
/// not be recorded.
///
/// ```dart
/// PostHogMaskWidget(
///   child: Text('Sensitive data'),
/// );
/// ```
class PostHogMaskWidget extends StatefulWidget {
  final Widget child;

  const PostHogMaskWidget({
    super.key,
    required this.child,
  });

  @override
  PostHogMaskWidgetState createState() => PostHogMaskWidgetState();
}

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
    return Container(
      key: _widgetKey,
      child: widget.child,
    );
  }
}
