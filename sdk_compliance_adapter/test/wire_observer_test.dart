import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/wire_observer.dart';

void main() {
  test('reset isolates late traffic from a closed SDK', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 19312);
    addTearDown(() => upstream.close(force: true));
    final wire = WireObserver();
    await wire.start(19313);
    addTearDown(wire.close);
    final oldUrl = wire.url;
    wire.reset();
    wire.target = Uri.parse('http://127.0.0.1:${upstream.port}');
    var count = 0;
    upstream.listen((request) async {
      count++;
      await request.drain<void>();
      await request.response.close();
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final stale = await client.postUrl(Uri.parse('$oldUrl/flags?v=2'));
    final response = await stale.close();
    expect(response.statusCode, 410);
    await response.drain<void>();
    expect(count, 0);
    expect(wire.requests, isEmpty);
    await expectLater(wire.waitForObservedCaptures(), throwsUnsupportedError);
  });
  test(
    'forwards compressed bytes and retry response without retrying',
    () async {
      final upstream = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        19312,
      );
      addTearDown(() => upstream.close(force: true));
      final wire = WireObserver();
      await wire.start(19313);
      wire.target = Uri.parse('http://127.0.0.1:${upstream.port}');
      addTearDown(wire.close);
      final body = gzip.encode(
        utf8.encode(
          jsonEncode({
            'batch': [
              {'event': 'hello', 'uuid': 'sdk-generated-id'},
            ],
          }),
        ),
      );
      final responseBody = gzip.encode(utf8.encode('{"error":"retry"}'));
      var count = 0;
      upstream.listen((request) async {
        count++;
        expect(request.uri.toString(), '/batch/?query=preserved');
        expect(request.headers.value('content-encoding'), 'gzip');
        expect(await request.fold<List<int>>([], (b, c) => b..addAll(c)), body);
        request.response.statusCode = 503;
        request.response.headers.set('retry-after', '3');
        request.response.headers.set('content-encoding', 'gzip');
        request.response.add(responseBody);
        await request.response.close();
      });
      final client = HttpClient()..autoUncompress = false;
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(
        Uri.parse('${wire.url}/batch/?query=preserved'),
      );
      request.headers.set('content-encoding', 'gzip');
      request.add(body);
      final response = await request.close();
      expect(response.statusCode, 503);
      expect(response.headers.value('retry-after'), '3');
      expect(response.headers.value('content-encoding'), 'gzip');
      expect(
        await response.fold<List<int>>([], (b, c) => b..addAll(c)),
        responseBody,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(count, 1);
      expect(wire.requests.single['body_base64'], base64Encode(body));
    },
  );

  test(
    'malformed observation does not replace the upstream response',
    () async {
      final upstream = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        19312,
      );
      addTearDown(() => upstream.close(force: true));
      final wire = WireObserver();
      await wire.start(19313);
      wire.target = Uri.parse('http://127.0.0.1:${upstream.port}');
      addTearDown(wire.close);
      upstream.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 201;
        request.response.write('upstream response');
        await request.response.close();
      });
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.postUrl(Uri.parse('${wire.url}/batch'));
      wire.expectCapture('hello');
      request.write('not JSON');
      final response = await request.close();
      expect(response.statusCode, 201);
      expect(await utf8.decoder.bind(response).join(), 'upstream response');
      await expectLater(wire.waitForObservedCaptures(), throwsStateError);
    },
  );
}
