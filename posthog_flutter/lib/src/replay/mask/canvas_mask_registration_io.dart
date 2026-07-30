import 'package:flutter/widgets.dart';

/// Canvas masking is a Flutter web concern; on every other platform
/// `PostHogMaskWidget` is honored by the native screenshot pipeline instead.
void notifyMaskWidgetMounted(BuildContext context) {}

void notifyMaskWidgetUnmounted(BuildContext context) {}
