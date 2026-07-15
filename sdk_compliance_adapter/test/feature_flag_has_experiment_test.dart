import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/adapter_server.dart';

void main() {
  test(
    r'$feature_flag_called includes $feature_flag_has_experiment from v2 metadata',
    () async {
      final mockServer = await _MockPostHogServer.start({
        'flags': {
          'experiment-flag': {
            'key': 'experiment-flag',
            'enabled': true,
            'variant': 'control',
            'metadata': {'has_experiment': true},
          },
        },
        'featureFlags': {'experiment-flag': 'control'},
      });
      addTearDown(mockServer.close);

      final properties = await _captureFeatureFlagCalled(
        mockServer,
        key: 'experiment-flag',
      );

      expect(properties[r'$feature_flag'], 'experiment-flag');
      expect(properties[r'$feature_flag_response'], 'control');
      expect(properties[r'$feature_flag_has_experiment'], isTrue);
    },
  );

  test(
    r'$feature_flag_has_experiment defaults to false without metadata',
    () async {
      final mockServer = await _MockPostHogServer.start({
        'featureFlags': {'plain-flag': true},
      });
      addTearDown(mockServer.close);

      final properties = await _captureFeatureFlagCalled(
        mockServer,
        key: 'plain-flag',
      );

      expect(properties[r'$feature_flag'], 'plain-flag');
      expect(properties[r'$feature_flag_response'], isTrue);
      expect(properties[r'$feature_flag_has_experiment'], isFalse);
    },
  );
}

/// Evaluates [key] through the adapter, flushes, and returns the properties of
/// the captured `$feature_flag_called` event.
Future<Map<String, Object?>> _captureFeatureFlagCalled(
  _MockPostHogServer mockServer, {
  required String key,
}) async {
  final adapter = ComplianceAdapter();
  final adapterServer = await adapter.start(port: 0);
  addTearDown(adapter.close);

  final adapterBase = 'http://127.0.0.1:${adapterServer.port}';
  await _postJson('$adapterBase/init', {
    'api_key': 'test-api-key',
    'host': mockServer.url,
    'flush_interval_ms': 60000,
  });

  final response = await _postJson('$adapterBase/get_feature_flag', {
    'key': key,
    'distinct_id': 'test-user',
  });
  expect(response['success'], isTrue);

  await _postJson('$adapterBase/flush', {});

  expect(mockServer.batchedEvents, hasLength(1));
  final event = mockServer.batchedEvents.single;
  expect(event['event'], r'$feature_flag_called');
  return Map<String, Object?>.from(event['properties'] as Map);
}

Future<Map<String, Object?>> _postJson(
  String url,
  Map<String, Object?> payload,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $body');
    }
    return Map<String, Object?>.from(jsonDecode(body) as Map);
  } finally {
    client.close(force: true);
  }
}

/// Serves `/flags/?v=2` with [flagsResponse] and records events posted to
/// `/batch`.
class _MockPostHogServer {
  _MockPostHogServer._(this._server, this._flagsResponse);

  final HttpServer _server;
  final Map<String, Object?> _flagsResponse;
  final List<Map<String, Object?>> batchedEvents = [];

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_MockPostHogServer> start(
    Map<String, Object?> flagsResponse,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mockServer = _MockPostHogServer._(server, flagsResponse);
    unawaited(mockServer._serve());
    return mockServer;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final body = await utf8.decoder.bind(request).join();
      if (request.method == 'POST' &&
          request.uri.path == '/flags/' &&
          request.uri.queryParameters['v'] == '2') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_flagsResponse));
        await request.response.close();
        continue;
      }

      if (request.method == 'POST' && request.uri.path == '/batch') {
        final decoded = jsonDecode(body) as Map;
        for (final event in decoded['batch'] as List) {
          batchedEvents.add(Map<String, Object?>.from(event as Map));
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 1}));
        await request.response.close();
        continue;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}
