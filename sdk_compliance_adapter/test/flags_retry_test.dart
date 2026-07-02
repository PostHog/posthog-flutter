import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/adapter_server.dart';

void main() {
  for (final statusCode in [502, 504]) {
    test(
      'retries /flags after HTTP $statusCode and returns flag value',
      () async {
        final flagsServer = await _FlagsServer.start([
          statusCode,
          HttpStatus.ok,
        ]);
        addTearDown(flagsServer.close);

        final adapter = ComplianceAdapter();
        final adapterServer = await adapter.start(port: 0);
        addTearDown(adapter.close);

        final adapterBase = 'http://127.0.0.1:${adapterServer.port}';
        await _postJson('$adapterBase/init', {
          'api_key': 'test-api-key',
          'host': flagsServer.url,
          'max_retries': 1,
          'flush_interval_ms': 60000,
        });

        final response = await _postJson('$adapterBase/get_feature_flag', {
          'key': 'retry-flag',
          'distinct_id': 'test-user',
        });

        expect(response['success'], isTrue);
        expect(response['value'], 'retry-success');
        expect(flagsServer.flagsRequestCount, 2);

        final state = await _getJson('$adapterBase/state');
        expect(state['total_retries'], 1);
      },
    );
  }

  test('propagates error after /flags retries are exhausted', () async {
    final flagsServer = await _FlagsServer.start([
      HttpStatus.badGateway,
      HttpStatus.badGateway,
    ]);
    addTearDown(flagsServer.close);

    final adapter = ComplianceAdapter();
    final adapterServer = await adapter.start(port: 0);
    addTearDown(adapter.close);

    final adapterBase = 'http://127.0.0.1:${adapterServer.port}';
    await _postJson('$adapterBase/init', {
      'api_key': 'test-api-key',
      'host': flagsServer.url,
      'max_retries': 1,
      'flush_interval_ms': 60000,
    });

    await expectLater(
      _postJson('$adapterBase/get_feature_flag', {
        'key': 'retry-flag',
        'distinct_id': 'test-user',
      }),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 500'),
        ),
      ),
    );

    expect(flagsServer.flagsRequestCount, 2);

    final state = await _getJson('$adapterBase/state');
    expect(state['total_retries'], 1);
    expect(state['last_error'], 'Feature flag request failed with HTTP 502');
  });
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

Future<Map<String, Object?>> _getJson(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
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

class _FlagsServer {
  _FlagsServer._(this._server, this._statuses);

  final HttpServer _server;
  final List<int> _statuses;
  int flagsRequestCount = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_FlagsServer> start(List<int> statuses) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final flagsServer = _FlagsServer._(server, List<int>.from(statuses));
    unawaited(flagsServer._serve());
    return flagsServer;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      await utf8.decoder.bind(request).join();
      if (request.method == 'POST' &&
          request.uri.path == '/flags/' &&
          request.uri.queryParameters['v'] == '2') {
        flagsRequestCount++;
        final statusCode =
            _statuses.isEmpty ? HttpStatus.ok : _statuses.removeAt(0);
        request.response.statusCode = statusCode;
        request.response.headers.contentType = ContentType.json;
        if (statusCode == HttpStatus.ok) {
          request.response.write(
            jsonEncode({
              'featureFlags': {'retry-flag': 'retry-success'},
            }),
          );
        } else {
          request.response.write(jsonEncode({'error': 'temporary failure'}));
        }
        await request.response.close();
        continue;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}
