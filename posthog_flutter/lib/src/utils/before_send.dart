import '../posthog_event.dart';
import '../util/logging.dart';

/// Runs [callbacks] in order against [event].
///
/// A null return drops the event and skips the rest of the list. A throw drops
/// the event too.
PostHogEvent? applyBeforeSend(
  List<PostHogEvent? Function(PostHogEvent)> callbacks,
  PostHogEvent event,
) {
  for (final callback in callbacks) {
    try {
      final result = callback(event);
      if (result == null) return null;
      event = result;
    } catch (e) {
      printIfDebug(
        '[PostHog] Warning: beforeSend callback threw an exception; dropping event: $e',
      );
      return null;
    }
  }
  return event;
}
