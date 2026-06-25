import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/native_communicator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('NativeCommunicator.captureNativeScreenshot', () {
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('returns the bytes when native returns a non-empty payload', () async {
      final payload = Uint8List.fromList([1, 2, 3, 4]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'captureNativeScreenshot');
        return payload;
      });

      final result = await NativeCommunicator()
          .captureNativeScreenshot(x: 0, y: 0, width: 10, height: 10);

      expect(result, payload);
    });

    test('returns null when native returns null', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);

      final result = await NativeCommunicator()
          .captureNativeScreenshot(x: 0, y: 0, width: 10, height: 10);

      expect(result, isNull);
    });

    test('returns null when native returns empty bytes', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => Uint8List(0));

      final result = await NativeCommunicator()
          .captureNativeScreenshot(x: 0, y: 0, width: 10, height: 10);

      expect(result, isNull);
    });

    test('returns null when the channel throws', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'boom'),
      );

      final result = await NativeCommunicator()
          .captureNativeScreenshot(x: 0, y: 0, width: 10, height: 10);

      expect(result, isNull);
    });
  });
}
