import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_error_tracking_autocapture_integration.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_exception.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';

import 'posthog_flutter_platform_interface_fake.dart';

void main() {
  group('Isolate Error Handler', () {
    final fake = PosthogFlutterPlatformFake();
    late PostHogErrorTrackingConfig config;
    late PostHogErrorTrackingAutoCaptureIntegration? integration;

    setUp(() {
      // Initialize Flutter binding first (like posthog_observer_test.dart)
      TestWidgetsFlutterBinding.ensureInitialized();
      // Set the fake as the global platform interface instance
      PosthogFlutterPlatformInterface.instance = fake;
      config = PostHogErrorTrackingConfig();
      integration = null;
    });

    tearDown(() {
      integration?.stop();
      PostHogErrorTrackingAutoCaptureIntegration.uninstall();
      // Clear fake state and restore original instance
      fake.capturedExceptions.clear();
      PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
    });

    group('Automatic Isolate Error Capture', () {
      setUp(() {
        config.captureIsolateErrors = true;
        integration = PostHogErrorTrackingAutoCaptureIntegration.install(
          config: config,
          posthog: fake,
        );
      });

      test('captures unhandled exceptions automatically', () async {
        // Wait for integration to set up
        await Future.delayed(const Duration(milliseconds: 100));

        // Clear any existing captured exceptions
        fake.capturedExceptions.clear();

        // Create an actual isolate error by spawning an isolate that throws
        // This will trigger the isolate error handler
        await Isolate.spawn(_isolateErrorFunction, 'Unhandled isolate error for testing');

        // Wait for the error to be processed
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify the error was captured automatically
        expect(fake.capturedExceptions, isNotEmpty);
        final capturedCall = fake.capturedExceptions.first;
        expect(capturedCall.error, isA<PostHogException>());

        final postHogException = capturedCall.error as PostHogException;
        expect(postHogException.mechanism, 'isolateError');
        expect(postHogException.handled, false);
        expect(postHogException.source,
            contains('Unhandled isolate error for testing'));
      });

      test('captures different error types automatically', () async {
        await Future.delayed(const Duration(milliseconds: 50));
        fake.capturedExceptions.clear();

        // Create unhandled ArgumentError in isolate
        await Isolate.spawn(_isolateErrorFunction, 'Invalid argument for isolate test');

        // Wait a bit then create another error
        await Future.delayed(const Duration(milliseconds: 100));

        await Isolate.spawn(_isolateErrorFunction, 'Custom isolate exception');

        // Wait for both errors to be processed
        await Future.delayed(const Duration(milliseconds: 200));

        expect(fake.capturedExceptions.length, 2);

        final errors = fake.capturedExceptions
            .map((call) => (call.error as PostHogException).source as String)
            .toList();

        expect(errors.any((error) => error.contains('Invalid argument')), true);
        expect(
            errors.any((error) => error.contains('Custom isolate exception')),
            true);
      });

      test('includes stack trace in automatically captured errors', () async {
        await Future.delayed(const Duration(milliseconds: 50));
        fake.capturedExceptions.clear();

        // Create an unhandled error in isolate that will have a real stack trace
        await Isolate.spawn(_isolateErrorFunction, 'Error with stack trace');

        // Wait for the error to be processed
        await Future.delayed(const Duration(milliseconds: 200));

        expect(fake.capturedExceptions, isNotEmpty);

        final capturedCall = fake.capturedExceptions.first;
        expect(capturedCall.stackTrace, isNotNull);
        expect(capturedCall.stackTrace.toString(), isNotEmpty);

        // Verify it's a PostHogException with isolateError mechanism
        final postHogException = capturedCall.error as PostHogException;
        expect(postHogException.mechanism, 'isolateError');
        expect(postHogException.source, contains('Error with stack trace'));
      });
    });
  });
}

/// Function to run in an isolate that will throw an error
void _isolateErrorFunction(String message) {
  // This will cause an isolate error
  throw Exception('Isolate error: $message');
}
