import 'package:flutter/material.dart';

class PostHogMaskWidget extends StatefulWidget {
  final Widget child;

  const PostHogMaskWidget({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  _PostHogMaskWidgetState createState() => _PostHogMaskWidgetState();
}

class _PostHogMaskWidgetState extends State<PostHogMaskWidget> {
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
