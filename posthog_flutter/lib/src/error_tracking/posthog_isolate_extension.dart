import 'dart:async';
import 'dart:isolate';

import '../posthog.dart';
import 'posthog_exception.dart';

/// Forwards uncaught errors from an isolate to PostHog.
extension PostHogIsolateExtension on Isolate {
  /// Captures this isolate's uncaught errors using [Posthog.captureException].
  ///
  /// Call from the main isolate after initializing PostHog. This does not
  /// require `errorTrackingConfig.captureIsolateErrors` to be enabled.
  /// Errors are reported as unhandled, with the background stack trace and
  /// this isolate's debug name. Dart supplies the error as a string, not the
  /// original exception object.
  ///
  /// Spawn the isolate paused, add the listener, then resume it to avoid
  /// missing errors before the listener is registered:
  ///
  /// ```dart
  /// final isolate = await Isolate.spawn(worker, message, paused: true);
  /// final listener = isolate.addPostHogErrorListener();
  /// isolate.resume(isolate.pauseCapability!);
  /// ```
  ///
  /// Returns the listener port. Pass it to [removePostHogErrorListener] to
  /// stop forwarding and close the port. The listener is also removed and
  /// its port closed automatically when this isolate exits.
  /// Existing error listeners and fatal-error behavior are unchanged.
  /// Each call installs a separate listener, so call only once per isolate.
  ///
  /// Not supported on Flutter web, which has no isolates.
  RawReceivePort addPostHogErrorListener() {
    final isolateName = debugName;
    final port = RawReceivePort()..keepIsolateAlive = false;

    port.handler = (Object? message) {
      if (message == null) {
        removePostHogErrorListener(port);
      } else if (message case [String error, String? stack]) {
        unawaited(Posthog().captureException(
          error: PostHogException(
            source: error,
            mechanism: 'onuncaughtexception',
            handled: false,
          ),
          stackTrace: stack == null ? null : StackTrace.fromString(stack),
          properties: {
            '\$exception_source': 'dart.isolate_error_listener',
            if (isolateName != null) 'isolate_name': isolateName,
          },
        ));
      }
    };

    addErrorListener(port.sendPort);
    addOnExitListener(port.sendPort);
    return port;
  }

  /// Stops forwarding errors and closes the listener's port.
  ///
  /// Pass the [listener] returned by [addPostHogErrorListener] on this isolate.
  /// Removes both the error listener and its automatic exit-cleanup listener.
  /// Calling this again, including after the isolate exits, is safe.
  void removePostHogErrorListener(RawReceivePort listener) {
    removeErrorListener(listener.sendPort);
    removeOnExitListener(listener.sendPort);
    listener.close();
  }
}
