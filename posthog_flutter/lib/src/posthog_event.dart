/// Represents an event that can be modified or dropped before it is sent.
///
/// This class is used in before-send callbacks to allow modification of events
/// before they are sent to PostHog.
///
/// On iOS, macOS, Android, Windows and Linux the callbacks get the event the
/// SDK is about to send, with its system and registered properties already
/// added. On iOS, macOS and Android it also carries its [uuid], [distinctId]
/// and [timestamp].
///
/// ```dart
/// config.beforeSend = [
///   (event) {
///     event.properties?.remove(r'$device_name');
///     return event;
///   },
/// ];
/// ```
class PostHogEvent {
  /// The name of the event (e.g., 'button_clicked', '$screen', '$exception')
  String event;

  /// The event's properties.
  ///
  /// On iOS, macOS, Android, Windows and Linux, the map already holds the
  /// system properties (like `$device_type` and `$session_id`), then the
  /// registered properties, then the event's own, and the event is sent as
  /// the callbacks leave it. `$set` and `$set_once` are in [userProperties]
  /// and [userPropertiesSetOnce] instead.
  ///
  /// On web, only the event's own properties are here; posthog-js adds the
  /// rest later.
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

  /// The event's unique id, a lowercase UUID v7.
  ///
  /// Set on iOS, macOS and Android, where the native SDK builds the event
  /// before the callbacks run. `null` on web, Windows and Linux. The id is
  /// kept even when a callback returns another [PostHogEvent].
  final String? uuid;

  /// The id of the person the event is captured for.
  ///
  /// Set on iOS, macOS and Android, where a callback can change it. `null` on
  /// web, Windows and Linux.
  String? distinctId;

  /// When the event happened.
  ///
  /// Set on iOS, macOS and Android, where a callback can change it. `null` on
  /// web, Windows and Linux.
  DateTime? timestamp;

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
  ///
  /// The optional [uuid], [distinctId] and [timestamp] are set by the SDK on
  /// iOS, macOS and Android.
  PostHogEvent({
    required this.event,
    this.properties,
    this.userProperties,
    this.userPropertiesSetOnce,
    this.options,
    this.uuid,
    this.distinctId,
    this.timestamp,
  });

  @override
  String toString() {
    return 'PostHogEvent(event: $event, uuid: $uuid, distinctId: $distinctId, timestamp: $timestamp, properties: $properties, userProperties: $userProperties, userPropertiesSetOnce: $userPropertiesSetOnce, options: $options)';
  }
}
