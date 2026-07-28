import 'package:flutter/scheduler.dart';

import '../web/web_canvas_mask_provider.dart';

/// A mounted `PostHogMaskWidget` is an explicit request for masking, so it
/// opts the app into canvas masking even when `posthog.init` never declared
/// `maskRegionsFn`.
///
/// Deferred to the end of the frame because `initState` runs during Flutter's
/// build phase: registering calls straight into posthog-js and restarts an
/// in-flight recording.
void notifyMaskWidgetMounted() {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    WebCanvasMaskProvider.notifyMaskWidgetMounted();
  });
}
