// ignore_for_file: avoid_dynamic_calls

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';
import 'package:posthog_flutter/src/error_tracking/posthog_exception.dart';

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
        result.containsKey('custom_key'),
        isTrue,
      ); // Properties are in root

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
        equals('Bad state: Test exception message'),
      ); // StateError adds prefix
      expect(
        mainExceptionData['thread_id'],
        isA<int>(),
      ); // Should be hash-based thread ID

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

      // Frames use PostHog's canonical bottom-up order: the crash site is the
      // last frame. Here the innermost frame of the input trace is
      // `Object.noSuchMethod`, so it must end up last.
      final crashFrame = frames.last;
      expect(crashFrame.containsKey('function'), isTrue);
      expect(crashFrame['function'], equals('Object.noSuchMethod'));
      expect(crashFrame['platform'], equals('dart'));

      // The application entry point (`main`) must appear before the crash site.
      final mainIndex = frames.indexWhere(
        (frame) => frame['filename'] == 'test.dart',
      );
      final noSuchMethodIndex = frames.lastIndexWhere(
        (frame) => frame['function'] == 'Object.noSuchMethod',
      );
      expect(mainIndex, greaterThanOrEqualTo(0));
      expect(
        mainIndex,
        lessThan(noSuchMethodIndex),
        reason: 'entry point should precede the crash site',
      );

      // Check that dart core frames are marked as not inApp
      final dartFrame = frames.firstWhere(
        (frame) =>
            frame['package'] == null &&
            (frame['abs_path']?.contains('dart:') == true),
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

      // Find frames by package
      final myAppFrame = frames.firstWhere((f) => f['package'] == 'my_app');
      final thirdPartyFrame = frames.firstWhere(
        (f) => f['package'] == 'third_party',
      );

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

      // Find frames by package
      final myAppFrame = frames.firstWhere((f) => f['package'] == 'my_app');
      final analyticsFrame = frames.firstWhere(
        (f) => f['package'] == 'analytics_lib',
      );
      final helperFrame = frames.firstWhere(
        (f) => f['package'] == 'helper_lib',
      );

      // Verify inApp detection
      expect(myAppFrame['in_app'], isTrue); // Default true, not excluded
      expect(analyticsFrame['in_app'], isFalse); // Explicitly excluded
      expect(helperFrame['in_app'], isTrue); // Default true, not excluded
    });

    test('gives precedence to inAppIncludes over inAppExcludes', () {
      // Test the precedence logic directly with a simple scenario
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString(
        '#0 test (package:test_package/test.dart:1:1)',
      );

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
        (frame) => frame['package'] == 'test_package',
        orElse: () => <String, dynamic>{},
      );

      // If we found the frame, test precedence
      if (testFrame.isNotEmpty) {
        expect(
          testFrame['in_app'],
          isTrue,
          reason: 'inAppIncludes should take precedence over inAppExcludes',
        );
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
          'expectedType': '_Exception',
        },
        {
          'exception': StateError('StateError test'),
          'expectedType': 'StateError',
        },
        {
          'exception': ArgumentError('ArgumentError test'),
          'expectedType': 'ArgumentError',
        },
        {
          'exception': FormatException('FormatException test'),
          'expectedType': 'FormatException',
        },
        // Primitive types
        {'exception': 'Plain string error', 'expectedType': 'String'},
        {'exception': 42, 'expectedType': 'int'},
        {'exception': true, 'expectedType': 'bool'},
        {'exception': 3.14, 'expectedType': 'double'},
        {'exception': [], 'expectedType': 'List<dynamic>'},
        {
          'exception': ['some', 'error'],
          'expectedType': 'List<String>',
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

        expect(
          exceptionData['type'],
          equals(expectedType),
          reason: 'Exception type mismatch for: $exception',
        );

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

      // Frames are emitted in canonical bottom-up order (crash site last), so
      // the three surviving user frames occupy the tail. The leading PostHog
      // wrapper frames (innermost) are stripped; the interior PostHog frame is
      // kept.
      final tail = frames.sublist(frames.length - 3);

      // Crash site (innermost of the input) is last.
      expect(tail[2]['package'], 'my_app');
      expect(tail[2]['filename'], 'main.dart');
      // Interior PostHog frame is preserved (only leading ones are stripped).
      expect(tail[1]['package'], 'posthog_flutter');
      expect(tail[1]['filename'], 'posthog.dart');
      // Entry point is first of the three.
      expect(tail[0]['package'], 'some_lib');
      expect(tail[0]['filename'], 'lib.dart');
    });

    test(
        'emits frames in canonical bottom-up order (entry point first, '
        'crash site last)', () {
      final exception = Exception('Test exception');

      // A linear (single-trace) synthetic stack in Dart's native
      // innermost-first order: the crash site is #0 and the entry point is #2.
      final stackTrace = StackTrace.fromString('''
#0      crashSite (package:my_app/crash.dart:10:3)
#1      middle (package:my_app/middle.dart:20:5)
#2      entryPoint (package:my_app/main.dart:30:7)
''');

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        inAppByDefault: true,
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      final entryIndex = frames.indexWhere(
        (frame) => frame['function'] == 'entryPoint',
      );
      final middleIndex = frames.indexWhere(
        (frame) => frame['function'] == 'middle',
      );
      final crashIndex = frames.indexWhere(
        (frame) => frame['function'] == 'crashSite',
      );

      expect(entryIndex, greaterThanOrEqualTo(0));
      expect(middleIndex, greaterThanOrEqualTo(0));
      expect(crashIndex, greaterThanOrEqualTo(0));

      // Canonical bottom-up: entry point precedes the crash site.
      expect(
        entryIndex,
        lessThan(middleIndex),
        reason: 'entry point must come before intermediate frames',
      );
      expect(
        middleIndex,
        lessThan(crashIndex),
        reason: 'crash site must be the last of the application frames',
      );

      // The crash site is the very last frame emitted.
      expect(
        frames.last['function'],
        equals('crashSite'),
        reason: 'the last frame must be the crash site',
      );
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

    test(
      'does not mark exceptions as synthetic when stack trace is provided',
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
      },
    );

    test('allows user properties to override system properties', () {
      final exception = Exception('Test exception');
      final stackTrace = StackTrace.fromString('#0 test (test.dart:1:1)');

      // Properties that override system properties
      final overrideProperties = {
        '\$exception_level': 'warning', // Override default 'error'
        'custom_property': 'custom_value', // Additional custom property
      };

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: stackTrace,
        properties: overrideProperties,
      );

      // Verify that user properties take precedence
      expect(result['\$exception_level'], equals('warning'));
      expect(result['custom_property'], equals('custom_value'));
    });

    test('inserts asynchronous gap frames between traces', () async {
      final exception = Exception('Async test exception');

      // Create an async stack trace by throwing from an async function
      StackTrace? asyncStackTrace;
      try {
        await _asyncFunction1();
      } catch (e, stackTrace) {
        asyncStackTrace = stackTrace;
      }

      final result = DartExceptionProcessor.processException(
        error: exception,
        stackTrace: asyncStackTrace,
      );

      final exceptionData =
          result['\$exception_list'] as List<Map<String, dynamic>>;
      final frames = exceptionData.first['stacktrace']['frames']
          as List<Map<String, dynamic>>;

      // Look for asynchronous gap frames
      final gapFrames = frames
          .where((frame) => frame['abs_path'] == '<asynchronous suspension>')
          .toList();

      // Should have at least one gap frame in an async stack trace
      expect(
        gapFrames,
        isNotEmpty,
        reason: 'Async stack traces should contain gap frames',
      );

      // Verify gap frame structure
      final gapFrame = gapFrames.first;
      expect(gapFrame['platform'], equals('dart'));
      expect(gapFrame['in_app'], isFalse);
      expect(gapFrame['abs_path'], equals('<asynchronous suspension>'));
    });

    test('processes PostHogException with different mechanism types', () {
      final testCases = [
        {'mechanism': 'FlutterError', 'handled': false},
        {'mechanism': 'PlatformDispatcher', 'handled': false},
        {'mechanism': 'UncaughtExceptionHandler', 'handled': true},
        {'mechanism': 'custom_mechanism', 'handled': true},
      ];

      for (final testCase in testCases) {
        final originalError = StateError('Test error');
        final postHogException = PostHogException(
          source: originalError,
          mechanism: testCase['mechanism'] as String,
          handled: testCase['handled'] as bool,
        );

        final result = DartExceptionProcessor.processException(
          error: postHogException,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionData =
            (result['\$exception_list'] as List).first as Map<String, dynamic>;

        expect(
          exceptionData['mechanism']['type'],
          equals(testCase['mechanism']),
        );
        expect(
          exceptionData['mechanism']['handled'],
          equals(testCase['handled']),
        );
        expect(exceptionData['type'], equals('StateError'));
      }
    });

    test(
      'uses original error for stack trace processing when wrapped in PostHogException',
      () {
        // Create an Error (not Exception) so it has a built-in stackTrace
        late Error originalError;

        try {
          throw StateError('Original error with stack trace');
        } catch (error) {
          originalError = error as Error;
        }

        // Wrap in PostHogException
        final postHogException = PostHogException(
          source: originalError,
          mechanism: 'test_mechanism',
          handled: true,
        );

        // Process without providing external stack trace - should use original error's stackTrace
        final result = DartExceptionProcessor.processException(
          error: postHogException,
          // No stackTrace provided - should extract from original error
        );

        final exceptionData =
            (result['\$exception_list'] as List).first as Map<String, dynamic>;

        // Verify it used the original error for processing
        expect(exceptionData['type'], equals('StateError'));
        expect(
          exceptionData['value'],
          equals('Bad state: Original error with stack trace'),
        );
        expect(exceptionData['mechanism']['type'], equals('test_mechanism'));
        expect(exceptionData['mechanism']['handled'], equals(true));

        // Should have stacktrace frames from the original error
        expect(exceptionData['stacktrace'], isNotNull);
        expect(exceptionData['stacktrace']['frames'], isA<List>());
        expect(
          (exceptionData['stacktrace']['frames'] as List).isNotEmpty,
          isTrue,
        );
      },
    );

    test('processes original error type correctly when wrapped', () {
      final testErrorTypes = [
        Exception('Test exception'),
        StateError('State error'),
        ArgumentError('Argument error'),
        FormatException('Format error'),
        RangeError('Range error'),
      ];

      for (final originalError in testErrorTypes) {
        final postHogException = PostHogException(
          source: originalError,
          mechanism: 'test_mechanism',
        );

        final result = DartExceptionProcessor.processException(
          error: postHogException,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionData =
            (result['\$exception_list'] as List).first as Map<String, dynamic>;

        // Should extract type from original error, not PostHogException
        final expectedType = originalError.runtimeType.toString();
        expect(exceptionData['type'], equals(expectedType));

        // Should use original error's toString for message
        expect(exceptionData['value'], equals(originalError.toString()));

        // But mechanism should come from wrapper
        expect(exceptionData['mechanism']['type'], equals('test_mechanism'));
      }
    });

    group('cause chain', () {
      final synchronousCases = <({
        String description,
        Object Function() buildError,
        StackTrace? stackTrace,
        List<String> expectedTypes,
        Map<int, String> expectedValues,
        void Function(List<Map<String, dynamic>>) extraExpectations,
      })>[
        (
          description:
              'walks AsyncError into multiple exception items, outermost-first',
          buildError: () {
            late StateError rootError;
            try {
              throw StateError('root cause');
            } catch (error) {
              rootError = error as StateError;
            }

            return AsyncError(rootError, rootError.stackTrace!);
          },
          stackTrace: null,
          expectedTypes: ['AsyncError', 'StateError'],
          expectedValues: {1: 'Bad state: root cause'},
          extraExpectations: (exceptionList) {
            // The cause carries its own (thrown) stack trace
            expect(exceptionList[1]['stacktrace'], isNotNull);
            expect(
              (exceptionList[1]['stacktrace']['frames'] as List).isNotEmpty,
              isTrue,
            );

            // Causes reuse the outer mechanism
            expect(exceptionList[1]['mechanism']['handled'], isTrue);
            expect(exceptionList[1]['mechanism']['type'], equals('generic'));
            expect(exceptionList[1]['mechanism']['synthetic'], isFalse);
          },
        ),
        (
          description: 'walks duck-typed cause getters',
          buildError: () {
            final root = FormatException('root');
            final middle = _ChainedException('middle', root);
            return _ChainedException('outer', middle);
          },
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
          expectedTypes: [
            '_ChainedException',
            '_ChainedException',
            'FormatException',
          ],
          expectedValues: {0: 'outer', 1: 'middle'},
          extraExpectations: (_) {},
        ),
        (
          description: 'does not add causes for errors without one',
          buildError: () => StateError('no cause'),
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
          expectedTypes: ['StateError'],
          expectedValues: const {},
          extraExpectations: (_) {},
        ),
      ];

      for (final testCase in synchronousCases) {
        test(testCase.description, () {
          final result = DartExceptionProcessor.processException(
            error: testCase.buildError(),
            stackTrace: testCase.stackTrace,
          );

          final exceptionList =
              result['\$exception_list'] as List<Map<String, dynamic>>;

          expect(exceptionList, hasLength(testCase.expectedTypes.length));
          for (final (index, expectedType) in testCase.expectedTypes.indexed) {
            expect(exceptionList[index]['type'], equals(expectedType));
          }
          for (final entry in testCase.expectedValues.entries) {
            expect(exceptionList[entry.key]['value'], equals(entry.value));
          }
          testCase.extraExpectations(exceptionList);
        });
      }

      test('walks ParallelWaitError to every failed future', () async {
        Object? caught;
        try {
          await [
            Future<int>.error(StateError('first parallel failure')),
            Future<int>.value(1),
            Future<int>.error(FormatException('second parallel failure')),
          ].wait;
        } catch (error) {
          caught = error;
        }

        expect(caught, isA<ParallelWaitError>());

        final result = DartExceptionProcessor.processException(error: caught!);

        final exceptionList =
            result['\$exception_list'] as List<Map<String, dynamic>>;

        expect(exceptionList, hasLength(5));
        expect(exceptionList[0]['type'], startsWith('ParallelWaitError'));
        expect(exceptionList[1]['type'], equals('AsyncError'));
        expect(exceptionList[2]['type'], equals('StateError'));
        expect(
          exceptionList[2]['value'],
          equals('Bad state: first parallel failure'),
        );
        expect(exceptionList[3]['type'], equals('AsyncError'));
        expect(exceptionList[4]['type'], equals('FormatException'));
        expect(
          exceptionList[4]['value'],
          equals('FormatException: second parallel failure'),
        );
      });

      test('guards against cause cycles', () {
        final a = _MutableCauseException('a');
        final b = _MutableCauseException('b');
        a.cause = b;
        b.cause = a;

        final result = DartExceptionProcessor.processException(
          error: a,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionList =
            result['\$exception_list'] as List<Map<String, dynamic>>;

        expect(exceptionList, hasLength(2));
        expect(exceptionList[0]['value'], equals('a'));
        expect(exceptionList[1]['value'], equals('b'));
      });

      test('caps the cause chain length', () {
        Object error = FormatException('root');
        for (var i = 0; i < 20; i++) {
          error = _ChainedException('wrapper $i', error);
        }

        final result = DartExceptionProcessor.processException(
          error: error,
          stackTrace: StackTrace.fromString('#0 test (test.dart:1:1)'),
        );

        final exceptionList =
            result['\$exception_list'] as List<Map<String, dynamic>>;

        expect(
          exceptionList,
          hasLength(DartExceptionProcessor.maxExceptionChainLength),
        );
        expect(exceptionList.first['value'], equals('wrapper 19'));
      });
    });
  });
}

/// Exception exposing the common duck-typed `cause` convention
class _ChainedException implements Exception {
  final String message;
  final Object? cause;

  _ChainedException(this.message, this.cause);

  @override
  String toString() => message;
}

/// Exception with a mutable cause, used to build cause cycles
class _MutableCauseException implements Exception {
  final String message;
  Object? cause;

  _MutableCauseException(this.message);

  @override
  String toString() => message;
}

// Helper functions to generate async stack traces for testing
Future<void> _asyncFunction1() async {
  await _asyncFunction2();
}

Future<void> _asyncFunction2() async {
  await Future.delayed(Duration.zero); // Force async boundary
  throw StateError('Async error for testing');
}
