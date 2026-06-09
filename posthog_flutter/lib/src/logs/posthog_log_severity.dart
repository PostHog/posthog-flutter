/// Severity level for a structured log record captured via
/// `Posthog().captureLog()` or the `Posthog().logger` facade.
///
/// The levels map to OpenTelemetry severity numbers (`trace`=1, `debug`=5,
/// `info`=9, `warn`=13, `error`=17, `fatal`=21). The mapping is performed by
/// the native SDKs; the Flutter layer forwards the level by [name] (lowercase),
/// which both the Android and Apple SDKs parse case-insensitively.
enum PostHogLogSeverity {
  /// Finest-grained diagnostic detail. High-volume; usually only enabled while
  /// diagnosing a problem.
  trace,

  /// Diagnostic detail useful during development.
  debug,

  /// Default level for regular runtime events.
  info,

  /// Something unexpected that is not yet an error.
  warn,

  /// A failure that should be looked at.
  error,

  /// A critical failure.
  fatal,
}
