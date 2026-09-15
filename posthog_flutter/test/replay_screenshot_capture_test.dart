import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_io.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/replay/screenshot/screenshot_capturer.dart';

import 'replay_capture_settle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late PosthogFlutterPlatformInterface previousPlatform;
  var sessionId = 'session-a';

  setUp(() {
    previousPlatform = PosthogFlutterPlatformInterface.instance;
    PosthogFlutterPlatformInterface.instance = PosthogFlutterIO();
    calls.clear();
    sessionId = 'session-a';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getSessionReplayState') {
        return {'isActive': true, 'sessionId': sessionId};
      }
      return null;
    });
  });

  tearDown(() async {
    await Posthog().close();
    messenger.setMockMethodCallHandler(channel, null);
    PosthogFlutterPlatformInterface.instance = previousPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  Future<PostHogConfig> mount(WidgetTester tester, double scale,
      {Size size = const Size(101, 99)}) async {
    final config = PostHogConfig('test_project_token')
      ..sessionReplay = true
      ..sessionReplayConfig.maskAllTexts = false
      ..sessionReplayConfig.maskAllImages = false
      ..sessionReplayConfig.screenshotScale = scale;
    await Posthog().setup(config);
    await tester.pumpWidget(Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: PostHogWidget(
          child: Stack(
            textDirection: TextDirection.ltr,
            fit: StackFit.expand,
            children: const [
              ColoredBox(color: Color(0xFF00FF00)),
              Positioned(
                left: 11,
                top: 9,
                width: 23,
                height: 21,
                child: PostHogMaskWidget(
                  child: ColoredBox(color: Color(0xFFFF00FF)),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await settleUntil(
        tester, () => calls.any((call) => call.method == 'sendFullSnapshot'));
    return config;
  }

  Future<ui.Image> decode(WidgetTester tester, Uint8List bytes) async {
    return (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }))!;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  for (final scale in [1.0, 0.5, 0.333, 0.1]) {
    testWidgets('Android scale $scale preserves geometry and masks',
        (tester) async {
      final config = await mount(tester, scale);
      final full =
          calls.firstWhere((call) => call.method == 'sendFullSnapshot');
      final args = full.arguments as Map;
      final image = await decode(tester, args['imageBytes'] as Uint8List);
      try {
        expect(image.width, (101 * scale).ceil());
        expect(image.height, (99 * scale).ceil());
        expect(args['width'], 101);
        expect(args['height'], 99);
        expect(args['x'], 0);
        expect(args['y'], 0);
        final meta = calls.firstWhere((call) => call.method == 'sendMetaEvent');
        expect((meta.arguments as Map)['width'], 101);
        expect((meta.arguments as Map)['height'], 99);
        expect(calls.indexOf(meta), lessThan(calls.indexOf(full)));

        final data = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        final pixels = data.buffer.asUint8List();
        expect(pixels.take(4), [0, 255, 0, 255]);
        for (var y = (9 * scale).floor(); y < (30 * scale).ceil(); y++) {
          for (var x = (11 * scale).floor(); x < (34 * scale).ceil(); x++) {
            final offset = (y * image.width + x) * 4;
            expect(pixels.sublist(offset, offset + 4), [0, 0, 0, 255],
                reason: 'mask pixel ($x, $y), scale $scale');
          }
        }
        for (var i = 0; i < pixels.length; i += 4) {
          expect(pixels[i] > 100 && pixels[i + 2] > 100 && pixels[i + 1] < 100,
              isFalse,
              reason: 'sensitive magenta must not survive downsampling');
        }
      } finally {
        image.dispose();
      }

      final capturer = ScreenshotCapturer(config);
      final placeholder =
          (await tester.runAsync(() => capturer.buildOcclusionPlaceholder()))!;
      final placeholderImage = await decode(tester, placeholder.imageBytes);
      try {
        expect(placeholderImage.width, (101 * scale).ceil());
        expect(placeholderImage.height, (99 * scale).ceil());
        expect(placeholder.width, 101);
        expect(placeholder.height, 99);
        final data = (await tester.runAsync(() =>
            placeholderImage.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
        final bytes = data.buffer.asUint8List();
        for (var i = 0; i < bytes.length; i += 4) {
          expect(bytes.sublist(i, i + 4), [0, 0, 0, 255]);
        }
      } finally {
        placeholderImage.dispose();
      }
      await unmount(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('fractional view sizes scale from the default raster dimensions',
      (tester) async {
    await mount(tester, 0.333, size: const Size(411.428571, 99.285714));
    final args = calls
        .firstWhere((call) => call.method == 'sendFullSnapshot')
        .arguments as Map;
    final image = await decode(tester, args['imageBytes'] as Uint8List);
    expect(image.width, (411 * 0.333).ceil());
    expect(image.height, (99 * 0.333).ceil());
    expect(args['width'], 411);
    expect(args['height'], 99);
    image.dispose();
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('scaled screenshots retain at least one pixel', (tester) async {
    await mount(tester, 0.1, size: const Size(1, 1));
    final args = calls
        .firstWhere((call) => call.method == 'sendFullSnapshot')
        .arguments as Map;
    final image = await decode(tester, args['imageBytes'] as Uint8List);
    expect(image.width, 1);
    expect(image.height, 1);
    expect(args['width'], 1);
    expect(args['height'], 1);
    image.dispose();
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'Android screenshot scale leaves iOS capture resolution unchanged',
      (tester) async {
    await mount(tester, 0.1);
    final args = calls
        .firstWhere((call) => call.method == 'sendFullSnapshot')
        .arguments as Map;
    final image = await decode(tester, args['imageBytes'] as Uint8List);
    expect(image.width, 101);
    expect(image.height, 99);
    expect(args['width'], 101);
    expect(args['height'], 99);
    image.dispose();
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
      'scaled frames deduplicate after delivery and rearm for a new session',
      (tester) async {
    await mount(tester, 0.5);
    calls.clear();
    await tester.pump(const Duration(seconds: 2));
    tester.binding.scheduleFrame();
    await tester.pump();
    await settleCapture(tester);
    expect(calls.where((call) => call.method == 'getSessionReplayState'),
        isNotEmpty);
    expect(calls.where((call) => call.method == 'sendFullSnapshot'), isEmpty);

    sessionId = 'session-b';
    calls.clear();
    await Posthog().reset();
    await tester.pump(const Duration(seconds: 2));
    await settleUntil(
        tester, () => calls.any((call) => call.method == 'sendFullSnapshot'));
    final meta = calls.indexWhere((call) => call.method == 'sendMetaEvent');
    final full = calls.indexWhere((call) => call.method == 'sendFullSnapshot');
    expect(meta, greaterThanOrEqualTo(0));
    expect(meta, lessThan(full));
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
