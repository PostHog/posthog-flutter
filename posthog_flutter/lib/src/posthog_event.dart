/// Represents an event that can be modified or dropped before it is sent.
///
/// This class is used in before-send callbacks to allow modification of events
/// before they are sent to PostHog.
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

  /// Creates an event passed to a before-send callback.
  ///
  /// The [event] is the event name to capture.
  ///
  /// The optional [properties] are event properties that can be amended before
  /// capture.
  ///
  /// The optional [userProperties] are person properties to set with `$set`.
  ///
  /// The optional [userPropertiesSetOnce] are person properties to set with
  /// `$set_once`.
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
