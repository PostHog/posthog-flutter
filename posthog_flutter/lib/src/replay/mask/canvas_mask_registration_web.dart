import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../util/logging.dart';
import '../web/web_canvas_mask_provider.dart';
import 'posthog_mask_controller.dart';

/// A mounted `PostHogMaskWidget` is an explicit request for masking, so it
/// opts the app into canvas masking even when `posthog.init` never declared
/// `maskRegionsFn`.
///
/// Deferred to the end of the frame because `initState` runs during Flutter's
/// build phase: registering calls straight into posthog-js and restarts an
/// in-flight recording.
void notifyMaskWidgetMounted(BuildContext context) {
  WebCanvasMaskProvider.registerMaskWidgetContext(context);
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!_isInTrackedTree(context)) {
      printIfDebug(
        'PostHog: this PostHogMaskWidget is outside the PostHogWidget tree '
        'PostHog tracks, so masking could never cover it — it does not '
        'enable web canvas masking.',
      );
      return;
    }
    WebCanvasMaskProvider.notifyMaskWidgetMounted();
  });
}

void notifyMaskWidgetUnmounted(BuildContext context) {
  WebCanvasMaskProvider.unregisterMaskWidgetContext(context);
}

/// The masking walk only sees PostHogWidget's subtree, so a mask widget
/// outside it would opt masking in while its own rects are never produced —
/// the walk would succeed and ship rects that do not cover the widget. With
/// no tracked tree at all the opt-in stays allowed: every walk then fails and
/// frames are skipped (fail closed), which is the documented behavior for an
/// app missing PostHogWidget.
///
/// The check runs once, in the mount's post-frame callback: a null tracked
/// context at that moment is treated as the no-PostHogWidget shape and
/// allowed. That one-shot allowance is backstopped by
/// [WebCanvasMaskProvider], which revalidates every mounted mask widget when
/// regions are computed — if a PostHogWidget later mounts without containing
/// this widget, frames are skipped (fail closed) rather than recorded
/// unmasked.
bool _isInTrackedTree(BuildContext context) {
  final trackedContext =
      PostHogMaskController.instance.containerKey.currentContext;
  if (trackedContext == null) {
    return true;
  }
  final tracked = trackedContext.findRenderObject();
  if (tracked == null) {
    // cannot prove the mask widget is outside the tracked tree
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final renderObject = context.findRenderObject();
  if (renderObject == null) {
    return false;
  }
  RenderObject? node = renderObject;
  while (node != null) {
    if (identical(node, tracked)) {
      return true;
    }
    node = node.parent;
  }
  return false;
}
