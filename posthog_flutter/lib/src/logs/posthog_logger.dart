import 'package:meta/meta.dart';

import 'posthog_log_severity.dart';

/// Signature used internally by [PostHogLogger] to forward a record to the
/// capture path. Not part of the public API.
@internal
typedef CaptureLog = Future<void> Function(
  String body,
  PostHogLogSeverity level,
  Map<String, Object>? attributes,
);

/// Per-level convenience facade for capturing structured logs.
///
/// Obtain it via `Posthog().logger`. Each helper captures a record at its
/// severity and is equivalent to calling `Posthog().captureLog(...)` with the
/// matching `level`.
///
/// **Example:**
/// ```dart
/// Posthog().logger.info('checkout completed', {'order_id': 'ord_789'});
/// Posthog().logger.error('payment failed', {'error_code': 'E001'});
/// ```
class PostHogLogger {
  final CaptureLog _capture;

  /// Creates a logger that forwards records through [capture].
  ///
  /// For internal use — obtain the logger via `Posthog().logger`.
  @internal
  PostHogLogger(CaptureLog capture) : _capture = capture;

  /// Captures a [PostHogLogSeverity.trace] record.
  Future<void> trace(String body, [Map<String, Object>? attributes]) =>
      _capture(body, PostHogLogSeverity.trace, attributes);

  /// Captures a [PostHogLogSeverity.debug] record.
  Future<void> debug(String body, [Map<String, Object>? attributes]) =>
      _capture(body, PostHogLogSeverity.debug, attributes);

  /// Captures a [PostHogLogSeverity.info] record.
  Future<void> info(String body, [Map<String, Object>? attributes]) =>
      _capture(body, PostHogLogSeverity.info, attributes);

  /// Captures a [PostHogLogSeverity.warn] record.
  Future<void> warn(String body, [Map<String, Object>? attributes]) =>
      _capture(body, PostHogLogSeverity.warn, attributes);

  /// Captures a [PostHogLogSeverity.error] record.
  Future<void> error(String body, [Map<String, Object>? attributes]) =>
      _capture(body, PostHogLogSeverity.error, attributes);

  /// Captures a [PostHogLogSeverity.fatal] record.
  Future<void> fatal(String body, [Map<String, Object>? attributes]) =>
      _capture(body, PostHogLogSeverity.fatal, attributes);
}
