@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/replay/web/web_canvas_mask_provider.dart';
import 'package:web/web.dart' as web;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  JSObject? capturedConfig;
  var stopRecordingCalls = 0;
  var startRecordingCalls = 0;

  JSObject installPosthogStub({
    JSObject? sessionRecording,
    bool withConfig = true,
    bool loaded = true,
    bool recordingStarted = false,
    bool declaresMaskProvider = true,
    String? version,
  }) {
    capturedConfig = null;
    stopRecordingCalls = 0;
    startRecordingCalls = 0;
    final stub = JSObject();
    if (withConfig) {
      final config = JSObject();
      if (declaresMaskProvider) {
        sessionRecording ??= JSObject();
        final existing =
            sessionRecording.getProperty<JSAny?>('canvasCapture'.toJS);
        final canvasCapture =
            existing.isA<JSObject>() ? existing as JSObject : JSObject();
        canvasCapture.setProperty('maskRegionsFn'.toJS, null);
        sessionRecording.setProperty('canvasCapture'.toJS, canvasCapture);
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
      }).toJS,
    );
    var recordingState = recordingStarted;
    stub.setProperty(
      'sessionRecordingStarted'.toJS,
      (() => recordingState.toJS).toJS,
    );
    stub.setProperty(
      'stopSessionRecording'.toJS,
      (() {
        stopRecordingCalls++;
        recordingState = false;
      }).toJS,
    );
    stub.setProperty(
      'startSessionRecording'.toJS,
      (() {
        startRecordingCalls++;
        recordingState = true;
      }).toJS,
    );
    if (version != null) {
      stub.setProperty('version'.toJS, version.toJS);
    }
    web.window.setProperty('posthog'.toJS, stub);
    return stub;
  }

  int Function() interceptWarns() {
    final consoleObject = web.window.getProperty<JSObject>('console'.toJS);
    final originalWarn = consoleObject.getProperty<JSAny?>('warn'.toJS);
    var warnCalls = 0;
    consoleObject.setProperty(
      'warn'.toJS,
      ((JSAny? message) {
        warnCalls++;
      }).toJS,
    );
    addTearDown(() => consoleObject.setProperty('warn'.toJS, originalWarn));
    return () => warnCalls;
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

  test('registers the mask provider via set_config', () {
    installPosthogStub();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final sessionRecording = capturedSessionRecording();
    final canvasCapture =
        sessionRecording.getProperty<JSObject>('canvasCapture'.toJS);
    expect(
      canvasCapture.getProperty<JSAny?>('maskRegionsFn'.toJS).isA<JSFunction>(),
      isTrue,
    );
    expect(
      sessionRecording.getProperty<JSAny?>('blockSelector'.toJS).dartify(),
      'flt-semantics-host',
    );
  });

  test('preserves existing session_recording config when merging', () {
    final existingCanvasCapture = JSObject()
      ..setProperty('resolutionScale'.toJS, 0.5.toJS);
    final existingCaptureCanvas = JSObject()
      ..setProperty('recordCanvas'.toJS, true.toJS)
      ..setProperty('canvasFps'.toJS, 2.toJS);
    final existingSessionRecording = JSObject()
      ..setProperty('blockSelector'.toJS, '.secret'.toJS)
      ..setProperty('maskAllInputs'.toJS, false.toJS)
      ..setProperty('canvasCapture'.toJS, existingCanvasCapture)
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
    final canvasCapture =
        sessionRecording.getProperty<JSObject>('canvasCapture'.toJS);
    expect(
      canvasCapture.getProperty<JSAny?>('resolutionScale'.toJS).dartify(),
      0.5,
    );
    expect(
      canvasCapture.getProperty<JSAny?>('maskRegionsFn'.toJS).isA<JSFunction>(),
      isTrue,
    );
    final captureCanvas =
        sessionRecording.getProperty<JSObject>('captureCanvas'.toJS);
    expect(
      captureCanvas.getProperty<JSAny?>('recordCanvas'.toJS).dartify(),
      true,
    );
    expect(
      captureCanvas.getProperty<JSAny?>('canvasFps'.toJS).dartify(),
      2,
    );
    expect(
      captureCanvas.getProperty<JSAny?>('maskRegionsFn'.toJS),
      isNull,
    );
  });

  test(
      'appends the semantics selector when an existing one only contains it '
      'as a substring', () {
    final existingSessionRecording = JSObject()
      ..setProperty('blockSelector'.toJS, '.not-flt-semantics-host'.toJS);
    installPosthogStub(sessionRecording: existingSessionRecording);

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(
      capturedSessionRecording()
          .getProperty<JSAny?>('blockSelector'.toJS)
          .dartify(),
      '.not-flt-semantics-host, flt-semantics-host',
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
        .getProperty<JSObject>('canvasCapture'.toJS)
        .getProperty<JSFunction>('maskRegionsFn'.toJS);
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
        .getProperty<JSObject>('canvasCapture'.toJS)
        .getProperty<JSFunction>('maskRegionsFn'.toJS);
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
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
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
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
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

  testWidgets('scales mask rects by an ancestor transform around the container',
      (tester) async {
    final config = PostHogConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      Transform.scale(
        scale: 2,
        alignment: Alignment.topLeft,
        child: PostHogWidget(
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
    flutterView.setAttribute('style', 'position: fixed; left: 0; top: 0');
    final canvas = web.document.createElement('canvas');
    canvas.setAttribute('style', 'position: absolute; left: 0; top: 0');
    flutterView.appendChild(canvas);
    web.document.body!.appendChild(flutterView);

    installPosthogStub();
    try {
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);
      final regions =
          regionsFn.callAsFunction(null, canvas) as JSArray<JSObject>;

      // container-local (0,0,30,40) outsets to (-1,-1,32,42), then doubles
      expect(regions.toDart, hasLength(1));
      final region = regions.toDart.first;
      expect(region.getProperty<JSNumber>('x'.toJS).toDartDouble, -2);
      expect(region.getProperty<JSNumber>('y'.toJS).toDartDouble, -2);
      expect(region.getProperty<JSNumber>('width'.toJS).toDartDouble, 64);
      expect(region.getProperty<JSNumber>('height'.toJS).toDartDouble, 84);
    } finally {
      flutterView.remove();
    }
  });

  testWidgets(
      'fails closed for a canvas in a foreign flutter-view on a multi-view '
      'page', (tester) async {
    final config = PostHogConfig('phc_test')
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false;

    await tester.pumpWidget(
      PostHogWidget(
        child: Align(
          alignment: Alignment.topLeft,
          child: PostHogMaskWidget(
            child: const SizedBox(width: 30, height: 40),
          ),
        ),
      ),
    );

    web.Element embeddedView(web.Element host) {
      final view = web.document.createElement('flutter-view');
      final canvas = web.document.createElement('canvas');
      view.appendChild(canvas);
      host.appendChild(view);
      return canvas;
    }

    final ownHost = web.document.createElement('div');
    final ownCanvas = embeddedView(ownHost);
    final foreignHost = web.document.createElement('div');
    final foreignCanvas = embeddedView(foreignHost);
    web.document.body!.appendChild(ownHost);
    web.document.body!.appendChild(foreignHost);

    installPosthogStub();
    try {
      WebCanvasMaskProvider.debugOwnViewHostOverride = ownHost;
      WebCanvasMaskProvider(config).register();

      final regionsFn = capturedSessionRecording()
          .getProperty<JSObject>('canvasCapture'.toJS)
          .getProperty<JSFunction>('maskRegionsFn'.toJS);

      expect(regionsFn.callAsFunction(null, foreignCanvas), isNull);
      final regions =
          regionsFn.callAsFunction(null, ownCanvas) as JSArray<JSObject>;
      expect(regions.toDart, hasLength(1));
    } finally {
      ownHost.remove();
      foreignHost.remove();
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

    final canvasCapture = JSObject()..setProperty('maskRegionsFn'.toJS, null);
    final sessionRecording = JSObject()
      ..setProperty('canvasCapture'.toJS, canvasCapture);
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

  test("a second register cancels the predecessor's retry chain", () async {
    web.window.setProperty('posthog'.toJS, null);
    capturedConfig = null;

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    final stub = installPosthogStub(recordingStarted: true);
    var setConfigCalls = 0;
    stub.setProperty(
      'set_config'.toJS,
      ((JSObject cfg) {
        setConfigCalls++;
        capturedConfig = cfg;
      }).toJS,
    );

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(setConfigCalls, 1);
    expect(stopRecordingCalls, 1);
    expect(capturedConfig, isNotNull);
  });

  test('retries the full apply when the restart throws on first register',
      () async {
    final stub = installPosthogStub(recordingStarted: true);
    var stopAttempts = 0;
    stub.setProperty(
      'stopSessionRecording'.toJS,
      (() {
        stopAttempts++;
        if (stopAttempts == 1) {
          throw StateError('stub stop failure');
        }
      }).toJS,
    );

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    expect(startRecordingCalls, 0);

    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(stopAttempts, 2);
    expect(startRecordingCalls, 1);
    expect(capturedConfig, isNotNull);
  });

  test('finishes the restart when stop succeeds but start throws', () async {
    final stub = installPosthogStub(recordingStarted: true);
    var startAttempts = 0;
    stub.setProperty(
      'startSessionRecording'.toJS,
      (() {
        startAttempts++;
        if (startAttempts == 1) {
          throw StateError('stub start failure');
        }
      }).toJS,
    );

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    // the stub now reports the recording as stopped, so the retry must not
    // skip the restart block
    expect(stopRecordingCalls, 1);
    expect(startAttempts, 1);

    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(startAttempts, 2);
    expect(stopRecordingCalls, 1);
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

  test('warns once but still registers when posthog-js is too old', () {
    installPosthogStub(version: '1.399.2');
    WebCanvasMaskProvider.debugMinPosthogJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(warns(), 1);
    expect(capturedConfig, isNotNull);
  });

  test('does not warn when posthog-js meets the minimum', () {
    installPosthogStub(version: '1.407.0');
    WebCanvasMaskProvider.debugMinPosthogJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(warns(), 0);
    expect(capturedConfig, isNotNull);
  });

  test('does not warn when posthog-js exposes no version', () {
    installPosthogStub();
    WebCanvasMaskProvider.debugMinPosthogJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(warns(), 0);
    expect(capturedConfig, isNotNull);
  });

  test('does not warn on an unparseable version', () {
    installPosthogStub(version: 'not-a-version');
    WebCanvasMaskProvider.debugMinPosthogJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(warns(), 0);
    expect(capturedConfig, isNotNull);
  });

  test('warns at most once across repeated applies', () {
    installPosthogStub(version: '1.399.2');
    WebCanvasMaskProvider.debugMinPosthogJsVersionOverride = '1.407.0';
    final warns = interceptWarns();

    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();
    WebCanvasMaskProvider(PostHogConfig('phc_test')).register();

    expect(warns(), 1);
  });
}
