/// Represents an event that can be modified or dropped by the [BeforeSendCallback].
///
/// This class is used in the beforeSend callback to allow modification of events before they are sent to PostHog.
class PostHogEvent {
  /// The name of the event (e.g., 'button_clicked', '$screen', '$exception')
  String event;

  /// User-provided properties for this event.
  ///
  /// Note: System properties (like $device_type, $session_id, etc.) are added
  /// by the native SDK at a later stage and are not available in this map.
  Map<String, Object?>? properties;

  PostHogEvent({
    required this.event,
    this.properties,
  });

  @override
  String toString() {
    return 'PostHogEvent(event: $event, properties: $properties)';
  }
}
