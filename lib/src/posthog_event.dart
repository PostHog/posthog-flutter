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
  Map<String, Object>? properties;

  /// User properties to set on the user profile ($set).
  ///
  /// These properties will be merged with any existing user properties.
  Map<String, Object>? userProperties;

  /// User properties to set only once on the user profile ($set_once).
  ///
  /// These properties will only be set if they don't already exist on the user profile.
  Map<String, Object>? userPropertiesSetOnce;

  PostHogEvent({
    required this.event,
    this.properties,
    this.userProperties,
    this.userPropertiesSetOnce,
  });

  @override
  String toString() {
    return 'PostHogEvent(event: $event, properties: $properties, userProperties: $userProperties, userPropertiesSetOnce: $userPropertiesSetOnce)';
  }
}
