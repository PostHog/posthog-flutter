import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/adapter_server.dart';

void main() {
  test('pending events leave with a batch the SDK gives up on', () async {
    final harness = await _Harness.start((request, _) async {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    });
    addTearDown(harness.close);

    await harness.captureAndFlush();

    final state = await harness.state();
    expect(state['pending_events'], 0);
    expect(state['total_events_sent'], 0);
  });

  test('a 303 reaches the SDK instead of being followed', () async {
    final harness = await _Harness.start((request, origin) async {
      request.response
        ..statusCode = HttpStatus.seeOther
        ..headers.set(HttpHeaders.locationHeader, '$origin/elsewhere');
      await request.response.close();
    });
    addTearDown(harness.close);

    await harness.captureAndFlush();

    expect(harness.paths, ['/i/v1/analytics/events']);
    expect((await harness.state())['total_events_sent'], 0);
  });

  test('the SDK follows a same-origin redirect through the proxy', () async {
    final harness = await _Harness.start((request, origin) async {
      if (request.uri.path == '/moved') {
        request.response.write('{}');
      } else {
        request.response
          ..statusCode = HttpStatus.temporaryRedirect
          ..headers.set(HttpHeaders.locationHeader, '$origin/moved');
      }
      await request.response.close();
    });
    addTearDown(harness.close);

    await harness.captureAndFlush();

    expect(harness.paths, ['/i/v1/analytics/events', '/moved']);
    expect((await harness.state())['total_events_sent'], 1);
  });

  test('a 2xx whose body breaks off stays delivered', () async {
    final harness = await _Harness.start((request, _) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n{');
      await socket.flush();
      socket.destroy();
    });
    addTearDown(harness.close);

    await harness.captureAndFlush();

    final state = await harness.state();
    expect(harness.paths, hasLength(1));
    expect(state['total_events_sent'], 1);
    expect(state['pending_events'], 0);
  });
}

class _Harness {
  _Harness._(this._ingestion, this._adapter, this._adapterPort, this._client);

  final HttpServer _ingestion;
  final ComplianceAdapter _adapter;
  final int _adapterPort;
  final HttpClient _client;
  final paths = <String>[];

  static Future<_Harness> start(
    Future<void> Function(HttpRequest request, String origin) respond,
  ) async {
    final ingestion = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final adapter = ComplianceAdapter();
    final adapterServer = await adapter.start(port: 0);
    final harness =
        _Harness._(ingestion, adapter, adapterServer.port, HttpClient());
    final origin = 'http://127.0.0.1:${ingestion.port}';
    unawaited(() async {
      await for (final request in ingestion) {
        harness.paths.add(request.uri.path);
        await request.drain<void>();
        await respond(request, origin);
      }
    }());
    await harness._post('/init', {
      'api_key': 'phc_test',
      'host': origin,
      'flush_at': 100,
      'flush_interval_ms': 60000,
    });
    return harness;
  }

  Future<void> captureAndFlush() async {
    await _post('/capture', {'distinct_id': 'user-1', 'event': 'evt'});
    await _post('/flush', {});
  }

  Future<Map<String, Object?>> state() async {
    final request = await _client.get('127.0.0.1', _adapterPort, '/state');
    return _decode(await request.close());
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final request = await _client.post('127.0.0.1', _adapterPort, path);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    return _decode(await request.close());
  }

  Future<Map<String, Object?>> _decode(HttpClientResponse response) async =>
      jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, Object?>;

  Future<void> close() async {
    await _adapter.close();
    _client.close(force: true);
    await _ingestion.close(force: true);
  }
}
