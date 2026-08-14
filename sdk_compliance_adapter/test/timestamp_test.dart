import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/adapter_server.dart';

void main() {
  test(
    'capture converts a non-UTC override to the equivalent UTC instant',
    () async {
      expect(
        await _captureTimestamp('2024-03-01T12:30:00-05:00'),
        '2024-03-01T17:30:00.000Z',
      );
    },
  );

  test('capture replaces an invalid timestamp with the current UTC time',
      () async {
    final beforeCapture = DateTime.now().toUtc();
    final timestamp = DateTime.parse(await _captureTimestamp('invalid'));

    expect(timestamp.isUtc, isTrue);
    expect(
      timestamp.difference(beforeCapture).abs(),
      lessThan(const Duration(seconds: 5)),
    );
  });
}

Future<String> _captureTimestamp(String timestamp) async {
  final uploadedBody = Completer<Map<String, Object?>>();
  final ingestion = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => ingestion.close(force: true));
  unawaited(() async {
    await for (final request in ingestion) {
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, Object?>;
      if (!uploadedBody.isCompleted) uploadedBody.complete(body);
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    }
  }());

  final adapter = ComplianceAdapter();
  final adapterServer = await adapter.start(port: 0);
  addTearDown(adapter.close);

  final client = HttpClient();
  addTearDown(client.close);
  final port = adapterServer.port;
  await _post(client, port, '/init', {
    'api_key': 'phc_test',
    'host': 'http://127.0.0.1:${ingestion.port}',
    'flush_at': 100,
    'flush_interval_ms': 60000,
  });
  await _post(client, port, '/capture', {
    'distinct_id': 'user-1',
    'event': 'order completed',
    'timestamp': timestamp,
  });
  await _post(client, port, '/flush', {});

  final body = await uploadedBody.future;
  final batch = body['batch'] as List<Object?>;
  final event = batch.single! as Map<String, Object?>;
  return event['timestamp']! as String;
}

Future<Map<String, Object?>> _post(
  HttpClient client,
  int port,
  String path,
  Map<String, Object?> body,
) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  return jsonDecode(await response.transform(utf8.decoder).join())
      as Map<String, Object?>;
}
