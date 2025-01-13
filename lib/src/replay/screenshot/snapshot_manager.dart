import 'package:flutter/cupertino.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

class SnapshotManager {
  // Expando is the equivalent of weakref
  final Expando<ViewTreeSnapshotStatus> _snapshotStatuses = Expando();

  ViewTreeSnapshotStatus getStatus(RenderObject renderObject) {
    return _snapshotStatuses[renderObject] ??= ViewTreeSnapshotStatus(false);
  }

  void updateStatus(RenderObject renderObject,
      {required bool shouldSendMetaEvent}) {
    final status = getStatus(renderObject);
    if (shouldSendMetaEvent) {
      status.sentMetaEvent = true;
    }
  }
}
