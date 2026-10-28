/// Represents an event that can be modified or dropped before it is sent.
///
/// This class is used in before-send callbacks to allow modification of events
/// before they are sent to PostHog.
class PostHogEvent {
  /// The name of the event (e.g., 'button_clicked', '$screen', '$exception')
  String event;

  /// User-provided properties for this event.
  ///
  /// On iOS, macOS, Android and web, system properties (like $device_type,
  /// $session_id, etc.) are added by the native SDK at a later stage and are
  /// not available in this map. On Windows and Linux, the map already holds
  /// them, then the registered properties, then the event's own, and the
  /// event is sent as the callbacks leave it.
  Map<String, Object>? properties;

  /// User properties to set on the user profile ($set).
  ///
  /// These properties will be merged with any existing user properties.
  Map<String, Object>? userProperties;

  /// User properties to set only once on the user profile ($set_once).
  ///
  /// These properties will only be set if they don't already exist on the user profile.
  Map<String, Object>? userPropertiesSetOnce;

  /// Settings that tell PostHog how to process this event, sent apart from
  /// its properties. See `Posthog.capture` for the known keys.
  ///
  /// A callback can read, add, change or remove them. A null value means
  /// unset.
  Map<String, Object?>? options;

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
  ///
  /// The optional [options] are the event's per-event options.
  PostHogEvent({
    required this.event,
    this.properties,
    this.userProperties,
    this.userPropertiesSetOnce,
    this.options,
  });

  @override
  String toString() {
    return 'PostHogEvent(event: $event, properties: $properties, userProperties: $userProperties, userPropertiesSetOnce: $userPropertiesSetOnce, options: $options)';
  }
}
