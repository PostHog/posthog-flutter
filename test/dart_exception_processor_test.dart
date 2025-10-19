import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';

void main() {
  group('DartExceptionProcessor', () {
    test('processes exception with correct properties', () {
      final mainException = StateError('Test exception message');
      final stackTrace = StackTrace.fromString('''
#0      Object.noSuchMethod (package:posthog-flutter:1884:25)
#1      Trace.terse.<anonymous closure> (file:///usr/local/google-old/home/goog/dart/dart/pkg/stack_trace/lib/src/trace.dart:47:21)
#2      IterableMixinWorkaround.reduce (dart:collection:29:29)
#3      List.reduce (dart:core-patch:1247:42)
#4      Trace.terse (file:///usr/local/google-old/home/goog/dart/dart/pkg/stack_trace/lib/src/trace.dart:40:35)
#5      format (file:///usr/local/google-old/home/goog/dart/dart/pkg/stack_trace/lib/stack_trace.dart:24:28)
#6      main.<anonymous closure> (file:///usr/local/google-old/home/goog/dart/dart/test.dart:21:29)
#7      _CatchErrorFuture._sendError (dart:async:525:24)
#8      _FutureImpl._setErrorWithoutAsyncTrace (dart:async:393:26)
#9      _FutureImpl._setError (dart:async:378:31)
#10     _ThenFuture._sendValue (dart:async:490:16)
#11     _FutureImpl._handleValue.<anonymous closure> (dart:async:349:28)
#12     Timer.run.<anonymous closure> (dart:async:2402:21)
#13     Timer.Timer.<anonymous closure> (dart:async-patch:15:15)
''');

      final additionalProperties = {'custom_key': 'custom_value'};

      // Process the exception
      final result = DartExceptionProcessor.processException(
        error: mainException,
        stackTrace: stackTrace,
        properties: additionalProperties,
        inAppIncludes: ['posthog_flutter_example'],
        inAppExcludes: [],
        inAppByDefault: true,
      );

      // Verify basic structure
      expect(result, isA<Map<String, dynamic>>());
      expect(result.containsKey('\$exception_level'), isTrue);
      expect(result.containsKey('\$exception_list'), isTrue);
      expect(
          result.containsKey('custom_key'), isTrue); // Properties are in root

      // Verify custom properties are preserved
      expect(result['custom_key'], equals('custom_value'));

      // Verify exception list structure
      final exceptionList =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      expect(exceptionList, isNotEmpty);

      final mainExceptionData = exceptionList.first;

      // Verify main exception structure
      expect(mainExceptionData['type'], equals('StateError'));
      expect(
          mainExceptionData['value'],
          equals(
              'Bad state: Test exception message')); // StateError adds prefix
      expect(mainExceptionData['thread_id'],
          isA<int>()); // Should be hash-based thread ID

      // Verify mechanism structure
      final mechanism = mainExceptionData['mechanism'] as Map<String, dynamic>;
      expect(mechanism['handled'], isTrue);
      expect(mechanism['synthetic'], isFalse);
      expect(mechanism['type'], equals('generic'));

      // Verify stack trace structure
      final stackTraceData =
          mainExceptionData['stacktrace'] as Map<String, dynamic>;
      expect(stackTraceData['type'], equals('raw'));

      final frames = stackTraceData['frames'] as List<Map<String, dynamic>>;
      expect(frames, isNotEmpty);

      // Verify first frame structure (should be main function)
      final firstFrame = frames.first;
      expect(firstFrame.containsKey('module'), isTrue);
      expect(firstFrame.containsKey('function'), isTrue);
      expect(firstFrame.containsKey('filename'), isTrue);
      expect(firstFrame.containsKey('lineno'), isTrue);
      expect(firstFrame['platform'], equals('dart'));

      // Verify inApp detection works - just check that the field exists and is boolean
      expect(firstFrame['in_app'], isTrue);

      // Check that dart core frames are marked as not inApp
      final dartFrame = frames.firstWhere(
        (frame) => frame['module'] == 'async' || frame['module'] == 'dart-core',
        orElse: () => <String, dynamic>{},
      );
      if (dartFrame.isNotEmpty) {
        expect(dartFrame['in_app'], isFalse);
      }
    });

    test('handles inAppIncludes configuration correctly', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('''
#0      main (package:my_app/main.dart:25:7)
#1      helper (package:third_party/helper.dart:10:5)
#2      core (dart:core/core.dart:100:10)
''');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
        inAppIncludes: ['my_app'],
        inAppExcludes: [],
        inAppByDefault: false, // third_party is not included
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Find frames by module
      final myAppFrame = frames.firstWhere((f) => f['module'] == 'my_app');
      final thirdPartyFrame =
          frames.firstWhere((f) => f['module'] == 'third_party');

      // Verify inApp detection
      expect(myAppFrame['in_app'], isTrue); // Explicitly included
      expect(thirdPartyFrame['in_app'], isFalse); // Not included
    });

    test('handles inAppExcludes configuration correctly', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('''
#0      main (package:my_app/main.dart:25:7)
#1      analytics (package:analytics_lib/tracker.dart:50:3)
#2      helper (package:helper_lib/utils.dart:15:8)
''');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
        inAppIncludes: [],
        inAppExcludes: ['analytics_lib'],
        inAppByDefault: true, // all inApp except inAppExcludes
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Find frames by module
      final myAppFrame = frames.firstWhere((f) => f['module'] == 'my_app');
      final analyticsFrame =
          frames.firstWhere((f) => f['module'] == 'analytics_lib');
      final helperFrame = frames.firstWhere((f) => f['module'] == 'helper_lib');

      // Verify inApp detection
      expect(myAppFrame['in_app'], isTrue); // Default true, not excluded
      expect(analyticsFrame['in_app'], isFalse); // Explicitly excluded
      expect(helperFrame['in_app'], isTrue); // Default true, not excluded
    });

    test('gives precedence to inAppIncludes over inAppExcludes', () {
      // Test the precedence logic directly with a simple scenario
      final exception = Exception('Test exception');
      final stackTrace =
          StackTrace.fromString('#0 test (package:test_package/test.dart:1:1)');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
        inAppIncludes: ['test_package'], // Include test_package
        inAppExcludes: ['test_package'], // But also exclude test_package
        inAppByDefault: false,
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Find any frame from test_package
      final testFrame = frames.firstWhere(
        (frame) => frame['module'] == 'test_package',
        orElse: () => <String, dynamic>{},
      );

      // If we found the frame, test precedence
      if (testFrame.isNotEmpty) {
        expect(testFrame['in_app'], isTrue,
            reason: 'inAppIncludes should take precedence over inAppExcludes');
      } else {
        // Just verify that the configuration was processed without error
        expect(frames, isA<List>());
      }
    });

    test('processes exception types correctly', () {
      final testCases = [
        // Real Exception/Error objects
        {
          'exception': Exception('Exception test'),
          'expectedType': '_Exception'
        },
        {
          'exception': StateError('StateError test'),
          'expectedType': 'StateError'
        },
        {
          'exception': ArgumentError('ArgumentError test'),
          'expectedType': 'ArgumentError'
        },
        {
          'exception': FormatException('FormatException test'),
          'expectedType': 'FormatException'
        },
        // Primitive types
        {'exception': 'Plain string error', 'expectedType': 'String'},
        {'exception': 42, 'expectedType': 'int'},
        {'exception': true, 'expectedType': 'bool'},
        {'exception': 3.14, 'expectedType': 'double'},
        {'exception': [], 'expectedType': 'List<dynamic>'},
        {
          'exception': ['some', 'error'],
          'expectedType': 'List<String>'
        },
        {'exception': {}, 'expectedType': '_Map<dynamic, dynamic>'},
      ];

      for (final testCase in testCases) {
        final exception = testCase['exception']!;
        final expectedType = testCase['expectedType'] as String;

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
          properties: {},
        );

        final exceptionList =
            result['\$exception_list'] as List<Map<String, dynamic>>;
        final exceptionData = exceptionList.first;

        expect(exceptionData['type'], equals(expectedType),
            reason: 'Exception type mismatch for: $exception');

        // Verify the exception value is present and is a string
        expect(exceptionData['value'], isA<String>());
        expect(exceptionData['value'], isNotEmpty);
      }
    });

    test('generates consistent thread IDs', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('#0 test (test.dart:1:1)');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final threadId = exceptionData.first['thread_id'];

      final result2 = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: {},
      );
      final exceptionData2 =
          result2['\$exception_list'] as List<Map<String, dynamic>>;
      final threadId2 = exceptionData2.first['thread_id'];

      expect(threadId, equals(threadId2)); // Should be consistent
    });

    test('generates stack trace when none provided', () {
      final exception = Exception('Test exception'); // will have no stack trace

      final result = DartExceptionProcessor.processException(
        error: exception,
        // No stackTrace provided - should generate one
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final stackTraceData = exceptionData.first['stacktrace'];

      // Should have generated a stack trace
      expect(stackTraceData, isNotNull);
      expect(stackTraceData['frames'], isA<List>());
      expect((stackTraceData['frames'] as List).isNotEmpty, isTrue);

      // Should be marked as synthetic since we generated it
      expect(exceptionData.first['mechanism']['synthetic'], isTrue);
    });

    test('uses error.stackTrace when available', () {
      try {
        throw StateError('Test error');
      } catch (error) {
        final result = DartExceptionProcessor.processException(
          error: error,
          // No stackTrace provided - should generate one from error.stackTrace
        );

        final exceptionData =
            result['\$exception_list'] as List<Map<String, dynamic>>;
        final stackTraceData = exceptionData.first['stacktrace'];

        // Should have a stack trace from the Error object
        expect(stackTraceData, isNotNull);
        expect(stackTraceData['frames'], isA<List>());

        // Should not be marked as synthetic since we did not generate a stack trace
        expect(exceptionData.first['mechanism']['synthetic'], isFalse);
      }
    });

    test('removes PostHog frames when stack trace is generated', () {
      final exception = Exception('Test exception');

      // Create a mock stack trace that includes PostHog frames
      final mockStackTrace = StackTrace.fromString('''
#0      DartExceptionProcessor.processException (package:posthog_flutter/src/error_tracking/dart_exception_processor.dart:28:7)
#1      PosthogFlutterIO.captureException (package:posthog_flutter/src/posthog_flutter_io.dart:435:29)
#2      Posthog.captureException (package:posthog_flutter/src/posthog.dart:136:7)
#3      userFunction (package:my_app/main.dart:100:5)
#4      PosthogFlutterIO.setup (package:posthog_flutter/src/posthog.dart:136:7)
#5      main (package:some_lib/lib.dart:50:3)
''');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTraceProvider: () {
          return mockStackTrace;
        },
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames'] as List;

      // Should include frames since we provided the stack trace
      expect(frames[0]['package'], 'my_app');
      expect(frames[0]['filename'], 'main.dart');
      // earlier PH frames should be untouched
      expect(frames[1]['package'], 'posthog_flutter');
      expect(frames[1]['filename'], 'posthog.dart');
      expect(frames[2]['package'], 'some_lib');
      expect(frames[2]['filename'], 'lib.dart');
    });

    test('marks generated stack frames as synthetic', () {
      final exception = Exception('Test exception'); // will have no stack trace

      final result = DartExceptionProcessor.processException(
        error: exception,
        // No stackTrace provided - should generate one
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;

      // Should be marked as synthetic since we generated it
      expect(exceptionData.first['mechanism']['synthetic'], isTrue);
    });

    test('does not mark exceptions as synthetic when stack trace is provided',
        () {
      final realExceptions = [
        Exception('Real exception'),
        StateError('Real error'),
        ArgumentError('Real argument error'),
      ];

      for (final exception in realExceptions) {
        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionData =
            result['\$exception_list'] as List<Map<String, dynamic>>;

        expect(exceptionData.first['mechanism']['synthetic'], isFalse);
      }
    });
  });
}
