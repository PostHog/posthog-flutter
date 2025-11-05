import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/src/util/platform_io_stub.dart';

import 'isolate_handler_io.dart'
    if (dart.library.html) 'isolate_handler_web.dart';
import 'package:posthog_flutter/src/util/logging.dart';

import '../posthog_flutter_platform_interface.dart';
import '../posthog_config.dart';
import 'posthog_exception.dart';

/// Handles automatic capture of Flutter and Dart exceptions
class PostHogErrorTrackingAutoCaptureIntegration {
  final PostHogErrorTrackingConfig _config;
  final PosthogFlutterPlatformInterface _posthog;

  // Store original handlers (we'll chain with them from our handler)
  FlutterExceptionHandler? _originalFlutterErrorHandler;
  ErrorCallback? _originalPlatformErrorHandler;

  // Isolate error handling
  final IsolateErrorHandler _isolateErrorHandler = IsolateErrorHandler();

  bool _isEnabled = false;

  static PostHogErrorTrackingAutoCaptureIntegration? _instance;

  PostHogErrorTrackingAutoCaptureIntegration._({
    required PostHogErrorTrackingConfig config,
    required PosthogFlutterPlatformInterface posthog,
  })  : _config = config,
        _posthog = posthog;

  /// Install the autocapture integration (can only be installed once)
  static PostHogErrorTrackingAutoCaptureIntegration? install({
    required PostHogErrorTrackingConfig config,
    required PosthogFlutterPlatformInterface posthog,
  }) {
    if (_instance != null) {
      debugPrint(
          'PostHog: Error tracking autocapture integration is already installed. Call PostHogErrorTrackingAutoCaptureIntegration.uninstall() first.');
      return null;
    }

    final instance = PostHogErrorTrackingAutoCaptureIntegration._(
      config: config,
      posthog: posthog,
    );

    _instance = instance;

    if (config.captureFlutterErrors ||
        config.capturePlatformDispatcherErrors ||
        config.captureIsolateErrors) {
      instance.start();
    }

    return instance;
  }

  /// Uninstall the autocapture integration
  static void uninstall() {
    if (_instance != null) {
      _instance?.stop();
      _instance = null;
    }
  }

  /// Start automatic exception capture
  void start() {
    if (_isEnabled) return;

    _isEnabled = true;

    // Set up Flutter error handler if enabled
    if (_config.captureFlutterErrors) {
      _setupFlutterErrorHandler();
    }

    // Set up platform error handler if enabled
    if (_config.capturePlatformDispatcherErrors) {
      _setupPlatformErrorHandler();
    }

    // Set up isolate error handler if enabled
    if (_config.captureIsolateErrors) {
      _setupIsolateErrorHandler();
    }
  }

  /// Stop automatic exception capture (restores original handlers)
  void stop() {
    if (!_isEnabled) return;

    _isEnabled = false;

    // Restore original handlers only if our own handler is still set
    if (FlutterError.onError == _posthogFlutterErrorHandler) {
      FlutterError.onError = _originalFlutterErrorHandler;
    }
    if (PlatformDispatcher.instance.onError == _posthogPlatformErrorHandler) {
      PlatformDispatcher.instance.onError = _originalPlatformErrorHandler;
    }

    // Clean up isolate error handler
    _isolateErrorHandler.removeErrorListener();

    // release refs
    _originalFlutterErrorHandler = null;
    _originalPlatformErrorHandler = null;
  }

  /// Flutter framework error handler
  void _setupFlutterErrorHandler() {
    // prevent circular calls
    if (FlutterError.onError == _posthogFlutterErrorHandler) {
      return;
    }

    _originalFlutterErrorHandler = FlutterError.onError;

    FlutterError.onError = _posthogFlutterErrorHandler;
  }

  void _posthogFlutterErrorHandler(FlutterErrorDetails details) {
    if (!details.silent || _config.captureSilentFlutterErrors) {
      // Collect additional context information
      //(see: https://github.com/getsentry/sentry-dart/blob/a69a51fd1695dd93024be80a50ad05dd990b2b82/packages/flutter/lib/src/integrations/flutter_error_integration.dart#L35-L60)
      final context = details.context?.toDescription();
      final collector = details.informationCollector?.call() ?? [];
      final information = collector.isNotEmpty
          ? (StringBuffer()..writeAll(collector, '\n')).toString()
          : null;
      final library = details.library;
      final errorSummary = details.toStringShort();

      // Build additional properties with Flutter-specific details
      final flutterErrorDetails = <String, Object>{
        if (context != null) 'context': context,
        if (information != null) 'information': information,
        if (library != null) 'library': library,
        'error_summary': errorSummary,
        'silent': details.silent,
      };

      final wrappedError = PostHogException(
          source: details.exception, mechanism: 'FlutterError', handled: false);

      _captureException(
        error: wrappedError,
        stackTrace: details.stack,
        properties: {'flutter_error_details': flutterErrorDetails},
      );
    } else {
      printIfDebug(
          "Error not captured because FlutterErrorDetails.silent is true and captureSilentFlutterErrors is false");
    }

    // Call the original handler, if any
    _originalFlutterErrorHandler?.call(details);
  }

  /// Platform error handler for Dart runtime errors
  void _setupPlatformErrorHandler() {
    // On web, PlatformDispatcher.onError is not implemented. Skip for now
    // See: https://github.com/flutter/flutter/issues/100277
    if (!isSupportedPlatform()) {
      return;
    }

    // prevent circular calls
    if (PlatformDispatcher.instance.onError == _posthogPlatformErrorHandler) {
      return;
    }

    _originalPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _posthogPlatformErrorHandler;
  }

  bool _posthogPlatformErrorHandler(Object error, StackTrace stackTrace) {
    final wrappedError = PostHogException(
      source: error,
      mechanism: 'PlatformDispatcher',
      handled: false,
    );

    _captureException(error: wrappedError, stackTrace: stackTrace);

    // Call the original handler, if any
    // False otherwise, so that default fallback mechanism is used
    return _originalPlatformErrorHandler?.call(error, stackTrace) ?? false;
  }

  /// Isolate error handler for current isolate errors
  void _setupIsolateErrorHandler() {
    if (!_config.captureIsolateErrors) {
      return;
    }

    _isolateErrorHandler.addErrorListener(_posthogIsolateErrorHandler);
  }

  void _posthogIsolateErrorHandler(Object? error) {
    // Isolate errors come as List<dynamic> with [errorString, stackTraceString]
    // See: https://api.dartlang.org/stable/2.7.0/dart-isolate/Isolate/addErrorListener.html
    if (error is List && error.length == 2) {
      final String errorString = error.first;
      final String? stackTraceString = error.last;
      final stackTrace = _parseStackTrace(stackTraceString);
      final isolateName = _isolateErrorHandler.isolateDebugName;

      final wrappedError = PostHogException(
        source: errorString,
        mechanism: 'isolateError',
        handled: false,
      );

      _captureException(
        error: wrappedError,
        stackTrace: stackTrace,
        properties: isolateName != null ? {'isolate_name': isolateName} : null,
      );
    }
  }

  StackTrace? _parseStackTrace(String? stackTraceString) {
    if (stackTraceString == null) return null;
    try {
      return StackTrace.fromString(stackTraceString);
    } catch (e) {
      printIfDebug('Failed to parse isolate stack trace: $e');
      return null;
    }
  }

  Future<void> _captureException({
    required PostHogException error,
    required StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) {
    return _posthog.captureException(
        error: error, stackTrace: stackTrace, properties: properties);
  }
}
