import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/native_communicator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('NativeCommunicator.captureNativeScreenshots', () {
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('returns list of bytes for each view', () async {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([5, 6, 7, 8]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'captureNativeScreenshots');
        return [a, b];
      });

      final result = await NativeCommunicator().captureNativeScreenshots([
        {'x': 0, 'y': 0, 'width': 10, 'height': 10},
        {'x': 10, 'y': 0, 'width': 10, 'height': 10},
      ]);

      expect(result, [a, b]);
    });

    test('returns list with nulls when native returns nulls', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => [null, null]);

      final result = await NativeCommunicator().captureNativeScreenshots([
        {'x': 0, 'y': 0, 'width': 10, 'height': 10},
        {'x': 10, 'y': 0, 'width': 10, 'height': 10},
      ]);

      expect(result, [null, null]);
    });

    test('returns empty list for empty input without calling native', () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        called = true;
        return [];
      });

      final result = await NativeCommunicator().captureNativeScreenshots([]);

      expect(result, isEmpty);
      expect(called, isFalse);
    });

    test('returns null-filled list when the channel throws', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'boom'),
      );

      final result = await NativeCommunicator().captureNativeScreenshots([
        {'x': 0, 'y': 0, 'width': 10, 'height': 10},
      ]);

      expect(result, [null]);
    });
  });
}
