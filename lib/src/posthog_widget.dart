import 'package:flutter/cupertino.dart';
import 'package:meta/meta.dart';
import 'package:posthog_flutter/src/screenshot/sentry_screenshot_widget.dart';

@internal
final postHogWidgetGlobalKey = GlobalKey(debugLabel: 'sentry_widget');

class PostHogWidget extends StatefulWidget {
  final Widget child;

  const PostHogWidget({super.key, required this.child});

  @override
  _PostHogWidgetState createState() => _PostHogWidgetState();
}

class _PostHogWidgetState extends State<PostHogWidget> {
  @override
  Widget build(BuildContext context) {
    Widget content = widget.child;
    content = PostHogScreenshotWidget(child: content);
    return Container(
      key: postHogWidgetGlobalKey,
      child: content,
    );
  }
}
