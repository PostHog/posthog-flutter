import 'package:flutter/material.dart';

class PostHogNoMaskWidget extends StatefulWidget {
  final Widget child;

  const PostHogNoMaskWidget({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  _PostHogNoMaskWidgetState createState() => _PostHogNoMaskWidgetState();
}

class _PostHogNoMaskWidgetState extends State<PostHogNoMaskWidget> {
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
