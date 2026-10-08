import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/posthog_core_stateless.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

import '../posthog_api_fake.dart';
import 'test_client.dart';

void main() {
  late LocalPostHogServer server;

  setUp(() async {
    server = await LocalPostHogServer.start();
  });

  group('Requests to PostHog', () {
    test('post gzip-compressed JSON with the SDK as the user agent', () async {
      final client = testClient(server);

      client.capture('desktop_event', properties: {'source': 'test'});
      await client.flush();

      final request = server.batchRequests.single;
      expect(request.headers['content-encoding'], 'gzip');
      expect(request.headers['content-type'], 'application/json');
      expect(request.headers['user-agent'],
          '$postHogFlutterSdkName/$postHogFlutterVersion');
      expect(request.body['api_key'], 'k');
      expect(request.eventNames, ['desktop_event']);
    });

    test('report an error status together with the response body', () async {
      final client = testClient(server);
      server.respond = (_) =>
          const PostHogResponse(HttpStatus.badRequest, body: 'invalid batch');

      client.capture('evt');

      await expectLater(
          client.flush(),
          throwsA(isA<PostHogFetchHttpError>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.responseBody, 'responseBody', 'invalid batch')));
    });

    test('leave a redirect unfollowed', () async {
      final target = await LocalPostHogServer.start();
      final client = testClient(server);
      server.respond = (_) => PostHogResponse(HttpStatus.seeOther,
          location: '${target.url}/flags/?v=2&config=true');

      // A /flags request is not retried after a redirect, unlike a batch.
      await client.reloadFeatureFlagsAsync();

      expect(server.flagsRequests, hasLength(1));
      expect(target.requests, isEmpty);
    });

    test('respects HTTP Retry-After without waiting inside flush', () async {
      final client = testClient(server);
      server.respond = (_) => const PostHogResponse(HttpStatus.tooManyRequests,
          headers: {'Retry-After': '120'});
      client.capture('event');

      await expectLater(client.flush().timeout(const Duration(seconds: 2)),
          throwsA(isA<PostHogFetchHttpError>()));
      await client.flush();

      expect(server.batchRequests, hasLength(1));
    });

    test('report a refused connection as a connection error', () async {
      final closed = await LocalPostHogServer.start();
      await closed.close();
      final storage = tempStorage();
      final client = testClient(closed, storage: storage);

      await client.reloadFeatureFlagsAsync();
      client.getFeatureFlag('beta-ui');

      expect(
          queuedPropsOf(
              storage, r'$feature_flag_called')[r'$feature_flag_error'],
          'connection_error');
    });

    test('aborts a request that becomes available after its timeout', () {
      fakeAsync((async) {
        final opened = Completer<HttpClientRequest>();
        final http = _ControlledHttpClient((_) => opened.future);
        late final client = HttpOverrides.runZoned(
          () => testClient(server),
          createHttpClient: (_) => http,
        );
        client.capture('evt');
        client.flush().catchError((Object _) {});
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10));
        final request = _ControlledRequest();
        opened.complete(request);
        async.flushMicrotasks();

        expect(request.abortCalls, 1);
        expect(request.closeCalls, 0,
            reason: 'a request opened after its deadline must not be sent');
        client.close();
        async.elapse(const Duration(seconds: 3));
      });
    });

    test('cancels response body reading before retrying a timeout', () {
      fakeAsync((async) {
        var bodyCancellationStarted = false;
        final bodyCancellationDone = Completer<void>();
        final body = StreamController<List<int>>(
          onCancel: () {
            bodyCancellationStarted = true;
            return bodyCancellationDone.future;
          },
        );
        final request = _ControlledRequest(
          response: _ControlledResponse(body.stream),
        );
        var openCalls = 0;
        final http = _ControlledHttpClient((_) async {
          openCalls++;
          if (openCalls == 1) return request;
          expect(bodyCancellationDone.isCompleted, isTrue,
              reason: 'retry must wait until the old response is cancelled');
          return _ControlledRequest();
        });
        late final client = HttpOverrides.runZoned(
          () => testClient(server),
          createHttpClient: (_) => http,
        );
        client.capture('evt');
        client.flush().catchError((Object _) {});
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        expect(bodyCancellationStarted, isTrue);
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(openCalls, 1,
            reason: 'retry must not overlap response cancellation');

        bodyCancellationDone.complete();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(openCalls, 2);
        client.close();
      });
    });
  });
}

class _ControlledHttpClient implements HttpClient {
  _ControlledHttpClient(this.openRequest);

  final Future<HttpClientRequest> Function(Uri uri) openRequest;

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openRequest(url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledRequest implements HttpClientRequest {
  _ControlledRequest({HttpClientResponse? response})
      : _response = response ?? _ControlledResponse(Stream.value(<int>[]));

  final HttpClientResponse _response;
  int abortCalls = 0;
  int closeCalls = 0;

  @override
  final headers = _ControlledHeaders();

  @override
  bool followRedirects = true;

  @override
  int contentLength = -1;

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    abortCalls++;
  }

  @override
  Future<HttpClientResponse> close() async {
    closeCalls++;
    return _response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _ControlledResponse(super.stream);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  final headers = _ControlledHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
