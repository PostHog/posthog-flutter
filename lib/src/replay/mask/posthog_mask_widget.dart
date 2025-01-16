import 'package:flutter/material.dart';

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
