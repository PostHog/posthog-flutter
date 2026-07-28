@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/web/web_canvas_mask_provider.dart';
import 'package:web/web.dart' as web;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  JSObject? capturedConfig;
  var setConfigCalls = 0;
  var stopRecordingCalls = 0;
  var startRecordingCalls = 0;

  JSObject installPosthogStub({
    JSObject? sessionRecording,
    bool withConfig = true,
    bool loaded = true,
    bool recordingStarted = false,
    bool declaresMaskProvider = true,
  }) {
    capturedConfig = null;
    setConfigCalls = 0;
    stopRecordingCalls = 0;
    startRecordingCalls = 0;
    final stub = JSObject();
    if (withConfig) {
      final config = JSObject();
      if (declaresMaskProvider) {
        sessionRecording ??= JSObject();
        final existing =
            sessionRecording.getProperty<JSAny?>('captureCanvas'.toJS);
        final captureCanvas =
            existing.isA<JSObject>() ? existing as JSObject : JSObject();
        captureCanvas.setProperty('canvasMaskRegionsFn'.toJS, null);
        sessionRecording.setProperty('captureCanvas'.toJS, captureCanvas);
      }
      if (sessionRecording != null) {
        config.setProperty('session_recording'.toJS, sessionRecording);
      }
      stub.setProperty('config'.toJS, config);
      // the real instance carries __loaded; the snippet stub (withConfig:
      // false) has neither config nor __loaded
      stub.setProperty('__loaded'.toJS, loaded.toJS);
    }
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        capturedConfig = cfg;
        setConfigCalls++;
      }).toJS,
    );
    stub.setProperty(
      'sessionRecordingStarted'.toJS,
      (() => recordingStarted.toJS).toJS,
    );
    stub.setProperty(
      'stopSessionRecording'.toJS,
      (() {
        stopRecordingCalls++;
      }).toJS,
    );
    stub.setProperty(
      'startSessionRecording'.toJS,
      (() {
        startRecordingCalls++;
      }).toJS,
    );
    web.window.setProperty('posthog'.toJS, stub);
    return stub;
  }

  // cancel the previous test's retry chain so a stale chain cannot apply
  // config against this test's stub
  setUp(WebCanvasMaskProvider.resetForTesting);

  tearDown(() {
    WebCanvasMaskProvider.resetForTesting();
    web.window.setProperty('posthog'.toJS, null);
  });

  JSObject capturedSessionRecording() {
    expect(capturedConfig, isNotNull);
    final sessionRecording =
        capturedConfig!.getProperty<JSAny?>('session_recording'.toJS);
    expect(sessionRecording.isA<JSObject>(), isTrue);
    return sessionRecording as JSObject;
  }

  test('leaves posthog-js untouched when the app declares no mask provider',
      () {
    installPosthogStub(declaresMaskProvider: true, recordingStarted: true);
    installPosthogStub(declaresMaskProvider: false, recordingStarted: true);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(capturedConfig, isNull);
    expect(stopRecordingCalls, 0);
    expect(startRecordingCalls, 0);
  });

  testWidgets('opts in when a PostHogMaskWidget mounted before register()',
      (tester) async {
    installPosthogStub(declaresMaskProvider: false, recordingStarted: true);

    await tester.pumpWidget(const PostHogMaskWidget(child: SizedBox.shrink()));
    expect(setConfigCalls, 0);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets('a mounted PostHogMaskWidget opts the app in on its own',
      (tester) async {
    installPosthogStub(declaresMaskProvider: false, recordingStarted: true);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    expect(capturedConfig, isNull);

    await tester.pumpWidget(const PostHogMaskWidget(child: SizedBox.shrink()));

    final sessionRecording = capturedSessionRecording();
    expect(
      sessionRecording
          .getProperty<JSObject>('captureCanvas'.toJS)
          .getProperty<JSAny?>('canvasMaskRegionsFn'.toJS)
          .isA<JSFunction>(),
      isTrue,
    );
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      'flt-semantics-host',
    );
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets('registers once however many PostHogMaskWidgets mount',
      (tester) async {
    installPosthogStub(declaresMaskProvider: false, recordingStarted: true);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    Widget maskWidgets(int count) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: List.generate(
              count,
              (_) => const PostHogMaskWidget(child: SizedBox.shrink()),
            ),
          ),
        );
    await tester.pumpWidget(maskWidgets(3));
    await tester.pumpWidget(maskWidgets(5));

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets(
      'a PostHogMaskWidget mount is a no-op when posthog.init already '
      'opted in', (tester) async {
    installPosthogStub(recordingStarted: true);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    expect(setConfigCalls, 1);

    await tester.pumpWidget(const PostHogMaskWidget(child: SizedBox.shrink()));

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  testWidgets(
      'an exception during the mount-triggered apply does not consume the '
      'opt-in', (tester) async {
    final stub = installPosthogStub(declaresMaskProvider: false);
    var calls = 0;
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        calls++;
        if (calls == 1) {
          throw StateError('stub failure');
        }
        capturedConfig = cfg;
      }).toJS,
    );

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    await tester.pumpWidget(const PostHogMaskWidget(child: SizedBox.shrink()));
    expect(capturedConfig, isNull);

    await tester.pump(const Duration(milliseconds: 600));

    expect(calls, 2);
    expect(capturedConfig, isNotNull);
  });

  testWidgets('opts in once posthog-js arrives after the widget mounted',
      (tester) async {
    web.window.setProperty('posthog'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    await tester.pumpWidget(const PostHogMaskWidget(child: SizedBox.shrink()));
    expect(capturedConfig, isNull);

    installPosthogStub(declaresMaskProvider: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(setConfigCalls, 1);
  });

  test('registers the mask provider via set_config', () {
    installPosthogStub();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final sessionRecording = capturedSessionRecording();
    final captureCanvas =
        sessionRecording.getProperty<JSObject>('captureCanvas'.toJS);
    expect(
      captureCanvas
          .getProperty<JSAny?>('canvasMaskRegionsFn'.toJS)
          .isA<JSFunction>(),
      isTrue,
    );
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      'flt-semantics-host',
    );
  });

  test('preserves existing session_recording config when merging', () {
    final existingCaptureCanvas = JSObject()
      ..setProperty('canvasFps'.toJS, 2.toJS);
    final existingSessionRecording = JSObject()
      ..setProperty('blockSelector'.toJS, '.secret'.toJS)
      ..setProperty('maskAllInputs'.toJS, false.toJS)
      ..setProperty('captureCanvas'.toJS, existingCaptureCanvas);
    installPosthogStub(sessionRecording: existingSessionRecording);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final sessionRecording = capturedSessionRecording();
    expect(
      sessionRecording.getProperty<JSAny?>('maskAllInputs'.toJS).dartify(),
      false,
    );
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      '.secret, flt-semantics-host',
    );
    final captureCanvas =
        sessionRecording.getProperty<JSObject>('captureCanvas'.toJS);
    expect(
      captureCanvas.getProperty<JSAny?>('canvasFps'.toJS).dartify(),
      2,
    );
    expect(
      captureCanvas
          .getProperty<JSAny?>('canvasMaskRegionsFn'.toJS)
          .isA<JSFunction>(),
      isTrue,
    );
  });

  test('blocks the semantics host even when maskAllTexts is false', () {
    installPosthogStub();
    final config = PostHogConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false;

    WebCanvasMaskProvider(config).register();

    final sessionRecording = capturedSessionRecording();
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      'flt-semantics-host',
    );
  });

  test('returns no regions for a canvas outside the flutter view', () {
    installPosthogStub();
    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final regionsFn = capturedSessionRecording()
        .getProperty<JSObject>('captureCanvas'.toJS)
        .getProperty<JSFunction>('canvasMaskRegionsFn'.toJS);
    final canvas = web.document.createElement('canvas');
    final regions = regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>;

    expect(regions.toDart, isEmpty);
  });

  test(
      'fails closed for a flutter-view canvas when no PostHogWidget is '
      'mounted', () {
    installPosthogStub();
    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final regionsFn = capturedSessionRecording()
        .getProperty<JSObject>('captureCanvas'.toJS)
        .getProperty<JSFunction>('canvasMaskRegionsFn'.toJS);
    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    try {
      expect(regionsFn.callAsFunction(null, canvas), isNull);
    } finally {
      flutterView.remove();
    }
  });

  test('warns once when the widget-tree walk keeps failing', () {
    installPosthogStub();
    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final consoleObject = web.window.getProperty<JSObject>('console'.toJS);
    final originalWarn = consoleObject.getProperty<JSAny?>('warn'.toJS);
    var warnCalls = 0;
    consoleObject.setProperty(
      'warn'.toJS,
      ((JSAny? message) {
        warnCalls++;
      }).toJS,
    );

    final flutterView = web.document.createElement('flutter-view');
    final canvas = web.document.createElement('canvas');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);
    try {
      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('captureCanvas'.toJS)
          .getProperty<JSFunction>('canvasMaskRegionsFn'.toJS);
      for (var i = 0; i < 12; i++) {
        expect(regionsFn.callAsFunction(null, canvas), isNull);
      }
      expect(warnCalls, 1);
    } finally {
      flutterView.remove();
      consoleObject.setProperty('warn'.toJS, originalWarn);
    }
  });

  testWidgets('maps mask rects into canvas-relative coordinates',
      (tester) async {
    final config = PostHogConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      PostHogWidget(
        child: Padding(
          padding: const EdgeInsets.only(left: 100, top: 200),
          child: Align(
            alignment: Alignment.topLeft,
            child: PostHogMaskWidget(
              child: const SizedBox(width: 30, height: 40),
            ),
          ),
        ),
      ),
    );

    final flutterView = web.document.createElement('flutter-view');
    flutterView.setAttribute('style', 'position: fixed; left: 50px; top: 60px');
    final canvas = web.document.createElement('canvas');
    canvas.setAttribute('style', 'position: absolute; left: 20px; top: 30px');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);

    installPosthogStub();
    try {
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('captureCanvas'.toJS)
          .getProperty<JSFunction>('canvasMaskRegionsFn'.toJS);
      final regions =
          regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>;

      expect(regions.toDart, hasLength(1));
      final region = regions.toDart.first;
      expect(region.getProperty<JSNumber>('x'.toJS).toDartDouble, 79);
      expect(region.getProperty<JSNumber>('y'.toJS).toDartDouble, 169);
      expect(region.getProperty<JSNumber>('width'.toJS).toDartDouble, 32);
      expect(region.getProperty<JSNumber>('height'.toJS).toDartDouble, 42);
    } finally {
      flutterView.remove();
    }
  });

  test('defers set_config until posthog-js exposes its config', () {
    installPosthogStub(withConfig: false);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(capturedConfig, isNull);
  });

  test('applies config after posthog-js appears with no snippet stub at all',
      () async {
    web.window.setProperty('posthog'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    expect(capturedConfig, isNull);

    installPosthogStub();
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(capturedConfig, isNotNull);
  });

  test(
      'applies config after array.js replaces the snippet stub with the real '
      'instance', () async {
    installPosthogStub(withConfig: false);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    expect(capturedConfig, isNull);

    installPosthogStub();
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(capturedConfig, isNotNull);
  });

  test(
      'keeps retrying while posthog is present but uninitialized, then '
      'applies once init declares the mask provider', () async {
    final stub = installPosthogStub(loaded: false, declaresMaskProvider: false);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // present-but-uninitialized must not be classified as not-opted-in
    expect(capturedConfig, isNull);

    final captureCanvas = JSObject()
      ..setProperty('canvasMaskRegionsFn'.toJS, null);
    final sessionRecording = JSObject()
      ..setProperty('captureCanvas'.toJS, captureCanvas);
    stub
        .getProperty<JSObject>('config'.toJS)
        .setProperty('session_recording'.toJS, sessionRecording);
    stub.setProperty('__loaded'.toJS, true.toJS);

    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(capturedConfig, isNotNull);
  });

  test('an exception during one retry tick does not kill the chain', () async {
    web.window.setProperty('posthog'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final stub = installPosthogStub();
    var setConfigCalls = 0;
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        setConfigCalls++;
        if (setConfigCalls == 1) {
          throw StateError('stub failure');
        }
        capturedConfig = cfg;
      }).toJS,
    );

    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(setConfigCalls, 2);
    expect(capturedConfig, isNotNull);
  });

  test('restarts an in-flight recording so the new config applies', () {
    installPosthogStub(recordingStarted: true);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(stopRecordingCalls, 1);
    expect(startRecordingCalls, 1);
  });

  test('does not restart recording when none is in flight', () {
    installPosthogStub();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(stopRecordingCalls, 0);
    expect(startRecordingCalls, 0);
  });
}
