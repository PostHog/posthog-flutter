import 'dart:ui';

import 'package:flutter/foundation.dart';
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

    if (config.captureFlutterErrors || config.capturePlatformDispatcherErrors) {
      instance.start();
    }

    return instance;
  }

  /// Uninstall the autocapture integration
  static void uninstall() {
    if (_instance != null) {
      _instance!.stop();
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
  }

  /// Stop automatic exception capture (restores original handlers)
  void stop() {
    if (!_isEnabled) return;

    _isEnabled = false;

    // Restore original handlers
    FlutterError.onError = _originalFlutterErrorHandler;
    PlatformDispatcher.instance.onError = _originalPlatformErrorHandler;
    _originalPlatformErrorHandler = null;
    _originalFlutterErrorHandler = null;
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
        if (context != null) 'context': 'thrown $context',
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

    // Call the original handler
    if (_originalFlutterErrorHandler != null) {
      try {
        _originalFlutterErrorHandler!(details);
      } catch (e) {
        // Pretty sure we should be doing this to avoid infinite loops
        debugPrint(
            'PostHog: Error in original FlutterError.onError handler: $e');
      }
    } else {
      // If no original handler, use the default behavior (default is to dump to console)
      FlutterError.presentError(details);
    }
  }

  /// Platform error handler for Dart runtime errors
  void _setupPlatformErrorHandler() {
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

    // Call the original handler
    if (_originalPlatformErrorHandler != null) {
      try {
        return _originalPlatformErrorHandler!(error, stackTrace);
      } catch (e) {
        debugPrint(
            'PostHog: Error in original PlatformDispatcher.onError handler: $e');
        return true; // Consider the error handled
      }
    }

    return false; // No original handler, don't modify behavior
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
