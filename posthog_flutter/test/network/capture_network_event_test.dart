import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/posthog.dart';
import 'package:posthog_flutter/src/posthog_config.dart';
import 'package:posthog_flutter/src/posthog_internal_events.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> methodCalls;

  setUp(() {
    methodCalls = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('posthog_flutter'),
      (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        if (methodCall.method == 'isSessionReplayActive') {
          return true;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('posthog_flutter'),
      null,
    );
    PostHogInternalEvents.sessionRecordingActive.value = false;
  });

  Future<PostHogConfig> _setupWithNetworkCapture({
    bool captureNetworkTelemetry = true,
    bool sessionReplay = true,
    String host = 'https://us.i.posthog.com',
  }) async {
    final config = PostHogConfig('test-api-key');
    config.host = host;
    config.sessionReplay = sessionReplay;
    config.sessionReplayConfig.captureNetworkTelemetry =
        captureNetworkTelemetry;
    await Posthog().setup(config);
    return config;
  }

  group('captureNetworkEvent', () {
    test('sends correctly formatted rrweb event', () async {
      await _setupWithNetworkCapture();

      await Posthog().captureNetworkEvent(
        url: 'https://api.example.com/users',
        method: 'GET',
        statusCode: 200,
        startTimestampMs: 1710854008431,
        endTimestampMs: 1710854009234,
        transferSize: 4521,
      );

      // Find the capture call (skip the setup call)
      final captureCalls =
          methodCalls.where((c) => c.method == 'capture').toList();
      expect(captureCalls, hasLength(1));

      final args = captureCalls.first.arguments as Map;
      expect(args['eventName'], '\$snapshot');

      final snapshotData =
          (args['properties'] as Map)['\$snapshot_data'] as List;
      expect(snapshotData, hasLength(1));

      final event = snapshotData[0] as Map;
      expect(event['type'], 5);
      expect(event['timestamp'], 1710854008431);

      final data = event['data'] as Map;
      expect(data['tag'], 'performanceSpan');

      final payload = data['payload'] as Map;
      expect(payload['op'], 'resource.fetch');
      expect(payload['description'], 'https://api.example.com/users');
      expect(payload['startTimestamp'], closeTo(1710854008.431, 0.001));
      expect(payload['endTimestamp'], closeTo(1710854009.234, 0.001));

      final payloadData = payload['data'] as Map;
      expect(payloadData['method'], 'GET');
      expect(payloadData['statusCode'], 200);
      expect((payloadData['response'] as Map)['size'], 4521);
    });

    test('does not send when captureNetworkTelemetry is disabled', () async {
      await _setupWithNetworkCapture(captureNetworkTelemetry: false);

      await Posthog().captureNetworkEvent(
        url: 'https://api.example.com/users',
        method: 'GET',
        statusCode: 200,
        startTimestampMs: 1710854008431,
        endTimestampMs: 1710854009234,
      );

      final captureCalls =
          methodCalls.where((c) => c.method == 'capture').toList();
      expect(captureCalls, isEmpty);
    });

    test('does not send when session replay is not active', () async {
      await _setupWithNetworkCapture();
      // Deactivate session recording after setup
      PostHogInternalEvents.sessionRecordingActive.value = false;

      await Posthog().captureNetworkEvent(
        url: 'https://api.example.com/users',
        method: 'GET',
        statusCode: 200,
        startTimestampMs: 1710854008431,
        endTimestampMs: 1710854009234,
      );

      final captureCalls =
          methodCalls.where((c) => c.method == 'capture').toList();
      expect(captureCalls, isEmpty);
    });

    test('filters out PostHog host URLs', () async {
      await _setupWithNetworkCapture(host: 'https://us.i.posthog.com');

      await Posthog().captureNetworkEvent(
        url: 'https://us.i.posthog.com/batch',
        method: 'POST',
        statusCode: 200,
        startTimestampMs: 1710854008431,
        endTimestampMs: 1710854009234,
      );

      final captureCalls =
          methodCalls.where((c) => c.method == 'capture').toList();
      expect(captureCalls, isEmpty);
    });

    test('sends event for failed requests with status 0', () async {
      await _setupWithNetworkCapture();

      await Posthog().captureNetworkEvent(
        url: 'https://api.example.com/timeout',
        method: 'POST',
        statusCode: 0,
        startTimestampMs: 1710854008431,
        endTimestampMs: 1710854018431,
        transferSize: 0,
      );

      final captureCalls =
          methodCalls.where((c) => c.method == 'capture').toList();
      expect(captureCalls, hasLength(1));

      final args = captureCalls.first.arguments as Map;
      final snapshotData =
          (args['properties'] as Map)['\$snapshot_data'] as List;
      final event = snapshotData[0] as Map;
      final payloadData =
          ((event['data'] as Map)['payload'] as Map)['data'] as Map;
      expect(payloadData['statusCode'], 0);
      expect((payloadData['response'] as Map)['size'], 0);
    });

    test('does not send when config is null (SDK not initialized)', () async {
      // Close SDK to clear config
      await Posthog().close();

      await Posthog().captureNetworkEvent(
        url: 'https://api.example.com/users',
        method: 'GET',
        statusCode: 200,
        startTimestampMs: 1710854008431,
        endTimestampMs: 1710854009234,
      );

      // Only close call, no capture calls
      final captureCalls =
          methodCalls.where((c) => c.method == 'capture').toList();
      expect(captureCalls, isEmpty);
    });

    test('defaults transferSize to 0', () async {
      await _setupWithNetworkCapture();

      await Posthog().captureNetworkEvent(
        url: 'https://api.example.com/users',
        method: 'DELETE',
        statusCode: 204,
        startTimestampMs: 1710854008431,
        endTimestampMs: 1710854008600,
      );

      final captureCalls =
          methodCalls.where((c) => c.method == 'capture').toList();
      expect(captureCalls, hasLength(1));

      final args = captureCalls.first.arguments as Map;
      final snapshotData =
          (args['properties'] as Map)['\$snapshot_data'] as List;
      final event = snapshotData[0] as Map;
      final payloadData =
          ((event['data'] as Map)['payload'] as Map)['data'] as Map;
      expect((payloadData['response'] as Map)['size'], 0);
    });
  });

  group('PostHogSessionReplayConfig', () {
    test('captureNetworkTelemetry defaults to false', () {
      final config = PostHogSessionReplayConfig();
      expect(config.captureNetworkTelemetry, false);
    });

    test('captureNetworkTelemetry is included in toMap()', () {
      final config = PostHogSessionReplayConfig();
      config.captureNetworkTelemetry = true;
      final map = config.toMap();
      expect(map['captureNetworkTelemetry'], true);
    });
  });
}
