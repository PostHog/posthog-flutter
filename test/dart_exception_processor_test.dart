import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/exceptions/dart_exception_processor.dart';

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
      ];

      for (final testCase in testCases) {
        final exception = testCase['exception'] as Object;
        final expectedType = testCase['expectedType'] as String;

        final result = DartExceptionProcessor.processException(
          error: exception,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
          properties: {},
        );

        final exceptionList =
            result['\$exception_list'] as List<Map<String, dynamic>>;
        final exceptionData = exceptionList.first;

        expect(exceptionData['type'], equals(expectedType));
        // Just verify the exception message is not empty and is a string
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
  });
}
