@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/error_tracking/dart_exception_processor.dart';

@JS('globalThis')
external JSObject get globalThis;

void setReleaseId(JSAny? value) {
  if (value == null) {
    globalThis.delete('_posthogReleaseId'.toJS);
    return;
  }
  globalThis['_posthogReleaseId'] = value;
}

Map<String, dynamic> process() {
  return DartExceptionProcessor.processException(
    error: StateError('boom'),
    stackTrace: StackTrace.current,
  );
}

void main() {
  group('DartExceptionProcessor release id', () {
    tearDown(() => setReleaseId(null));

    test('reports the release id posthog-cli injected into the chunk', () {
      setReleaseId('01a047ca-108d-0000-7487-e086f76d4aaf'.toJS);

      expect(process()[r'$release_id'], '01a047ca-108d-0000-7487-e086f76d4aaf');
    });

    // An absent or malformed global has to leave the property off entirely. An
    // empty or non-string value reaches the server as a release that resolves
    // to nothing, which is worse than no release at all.
    for (final (description, value) in <(String, JSAny?)>[
      ('nothing is injected', null),
      ('the global is an empty string', ''.toJS),
      ('the global is not a string', 42.toJS),
    ]) {
      test('omits the release id when $description', () {
        setReleaseId(value);

        expect(process().containsKey(r'$release_id'), isFalse);
      });
    }
  });
}
