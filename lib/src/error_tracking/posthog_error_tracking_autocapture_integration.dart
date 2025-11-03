import 'dart:ui';

import 'package:flutter/foundation.dart';

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
    // don't capture silent errors (could maybe be a config?)
    if (!details.silent) {
      _captureException(
        error: details.exception,
        stackTrace: details.stack,
        context: details.context?.toString(),
        mechanismType: 'FlutterError',
      );
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
    _captureException(
        error: error,
        stackTrace: stackTrace,
        mechanismType: 'PlatformDispatcher');

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
    required dynamic error,
    required StackTrace? stackTrace,
    String? context,
    String mechanismType = 'generic',
  }) {
    // Wrap the original error in PostHogException with mechanism information
    final wrappedError = PostHogException(
      source: error,
      mechanism: mechanismType,
      handled: false, // Always false for autocapture (unhandled exceptions)
    );

    return _posthog.captureException(
        error: wrappedError,
        stackTrace: stackTrace ?? StackTrace.current,
        properties: context != null ? {'context': context} : null);
  }
}
