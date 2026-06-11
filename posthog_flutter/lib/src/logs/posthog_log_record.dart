import 'posthog_log_severity.dart';

/// Represents a log record that can be modified or dropped before it is sent.
///
/// This class is passed to the before-send callbacks registered via
/// [PostHogLogsConfig.beforeSend] to allow modification of log records before
/// they are forwarded to the native SDK.
class PostHogLogRecord {
  /// The log message body.
  String body;

  /// The severity level of the record.
  PostHogLogSeverity level;

  /// User-provided attributes for this record.
  ///
  /// Note: Auto-captured context (distinct id, session id, screen name, app
  /// state, active feature flags) is added by the native SDK at a later stage
  /// and is not available in this map.
  Map<String, Object>? attributes;

  /// Creates a log record passed to a before-send callback.
  ///
  /// The [body] is the log message.
  ///
  /// The [level] is the severity, defaulting to [PostHogLogSeverity.info].
  ///
  /// The optional [attributes] are per-record attributes that can be amended
  /// before capture.
  PostHogLogRecord({
    required this.body,
    this.level = PostHogLogSeverity.info,
    this.attributes,
  });

  @override
  String toString() {
    return 'PostHogLogRecord(body: $body, level: ${level.name}, attributes: $attributes)';
  }
}
