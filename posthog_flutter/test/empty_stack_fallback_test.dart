import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';
import 'package:stack_trace/stack_trace.dart';

Never _throwOriginalError() => throw StateError('original failure');

void main() {
  final traces = <String, StackTrace?>{
    'null': null,
    'StackTrace.empty': StackTrace.empty,
    'StackTrace.fromString(empty)': StackTrace.fromString(''),
    'StackTrace.fromString(whitespace)': StackTrace.fromString(' \n\t'),
    'Trace.parse(empty)': Trace.parse(''),
    'Chain.parse(empty)': Chain.parse(''),
  };
  final captureStack = StackTrace.fromString(
    '#0 captureSite (package:my_app/capture.dart:10:1)',
  );

  for (final entry in traces.entries) {
    test('${entry.key} preserves the original Error stack', () {
      late Error error;
      try {
        _throwOriginalError();
      } catch (caught) {
        error = caught as Error;
      }
      expect(error.stackTrace, isNotNull);

      var generated = false;
      // The test runner's Chain.capture zone appends frames to empty traces.
      final result =
          Zone.root.run(() => DartExceptionProcessor.processException(
                error: error,
                stackTrace: entry.value,
                stackTraceProvider: () {
                  generated = true;
                  return captureStack;
                },
              ));
      final exception =
          (result['\$exception_list'] as List<Map<String, dynamic>>).first;
      final stack = exception['stacktrace'] as Map<String, dynamic>?;
      final frames = stack?['frames'] as List<Map<String, dynamic>>? ?? [];

      expect(
        frames.map((frame) => frame['function']),
        contains('_throwOriginalError'),
        reason: 'generated=$generated; mechanism=${exception['mechanism']}',
      );
      expect(generated, isFalse);
      expect(exception['mechanism'], containsPair('synthetic', false));
    });
  }

  for (final entry in traces.entries) {
    test('${entry.key} generates a fallback when no original exists', () {
      final result =
          Zone.root.run(() => DartExceptionProcessor.processException(
                error: Exception('no original stack'),
                stackTrace: entry.value,
                stackTraceProvider: () => captureStack,
              ));
      final exception =
          (result['\$exception_list'] as List<Map<String, dynamic>>).first;
      final stack = exception['stacktrace'] as Map<String, dynamic>?;
      final frames = stack?['frames'] as List<Map<String, dynamic>>? ?? [];

      expect(frames.map((frame) => frame['function']), contains('captureSite'));
      expect(exception['mechanism'], containsPair('synthetic', true));
    });
  }

  test('a usable supplied stack takes precedence over the original', () {
    try {
      _throwOriginalError();
    } catch (error) {
      final result =
          Zone.root.run(() => DartExceptionProcessor.processException(
                error: error,
                stackTrace: captureStack,
                stackTraceProvider: () =>
                    throw StateError('must use supplied stack'),
              ));
      final exception =
          (result['\$exception_list'] as List<Map<String, dynamic>>).first;
      final stack = exception['stacktrace'] as Map<String, dynamic>;
      final frames = stack['frames'] as List<Map<String, dynamic>>;

      expect(frames.map((frame) => frame['function']), ['captureSite']);
      expect(exception['mechanism'], containsPair('synthetic', false));
    }
  });
}
