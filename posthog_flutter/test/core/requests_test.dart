import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/core/posthog_core_stateless.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';
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
      expect(request.headers['authorization'], 'Bearer k');
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
      server.respond = (_) => const PostHogResponse(
          HttpStatus.serviceUnavailable,
          headers: {'Retry-After': '20'});
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
        // A 2xx whose body fails counts as delivered, so the status here is
        // one that is retried.
        final request = _ControlledRequest(
          response: _ControlledResponse(body.stream,
              statusCode: HttpStatus.serviceUnavailable),
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

    test('keeps a slow upload that makes progress going past 10 seconds', () {
      fakeAsync((async) {
        late final _ControlledRequest request;
        final http =
            _ControlledHttpClient((_) async => request = _ControlledRequest(
                  takeChunk: () =>
                      Future<void>.delayed(const Duration(seconds: 6)),
                ));
        final storage = tempStorage();
        late final client = HttpOverrides.runZoned(
          () => testClient(server, storage: storage),
          createHttpClient: (_) => http,
        );
        _captureLargeEvent(client);
        Object? error;
        var flushed = false;
        client.flush().then((_) => flushed = true, onError: (Object e) {
          error = e;
        });
        async.elapse(const Duration(seconds: 60));

        expect(request.chunks, greaterThan(2));
        expect(error, isNull);
        expect(flushed, isTrue);
        expect(request.abortCalls, 0);
        expect(getQueue(storage), isEmpty);
      });
    });

    test('times out an upload that stalls for 10 seconds', () {
      fakeAsync((async) {
        final stalled = Completer<void>();
        var taken = 0;
        final request = _ControlledRequest(
          takeChunk: () => taken++ == 0 ? Future.value() : stalled.future,
        );
        final http = _ControlledHttpClient((_) async => request);
        final storage = tempStorage();
        late final client = HttpOverrides.runZoned(
          () => testClient(server, storage: storage),
          createHttpClient: (_) => http,
        );
        _captureLargeEvent(client);
        Object? error;
        client.flush().catchError((Object e) {
          error = e;
        });
        async.elapse(const Duration(seconds: 10) - _ms);
        expect(error, isNull);
        async.elapse(_ms);

        expect(error, isA<PostHogFetchNetworkError>());
        expect(request.abortCalls, 1);
        expect(getQueue(storage), hasLength(1));
        client.close();
      });
    });

    test('keeps a response that trickles in going past 10 seconds', () {
      fakeAsync((async) {
        final body = StreamController<List<int>>();
        final http = _ControlledHttpClient((_) async =>
            _ControlledRequest(response: _ControlledResponse(body.stream)));
        late final client = HttpOverrides.runZoned(
          () => testClient(server),
          createHttpClient: (_) => http,
        );
        client.capture('evt');
        Object? error;
        var flushed = false;
        client.flush().then((_) => flushed = true, onError: (Object e) {
          error = e;
        });
        for (var i = 0; i < 4; i++) {
          async.elapse(const Duration(seconds: 6));
          body.add(utf8.encode(' '));
        }
        body.close();
        async.flushMicrotasks();

        expect(error, isNull);
        expect(flushed, isTrue);
      });
    });

    test('counts a 2xx whose body times out as delivered', () {
      fakeAsync((async) {
        // Cancelled in this zone: fake_async does not run the root zone's
        // microtasks.
        final body =
            StreamController<List<int>>(onCancel: () => Future<void>.value());
        var openCalls = 0;
        final http = _ControlledHttpClient((_) async {
          openCalls++;
          return _ControlledRequest(response: _ControlledResponse(body.stream));
        });
        final storage = tempStorage();
        late final client = HttpOverrides.runZoned(
          () => testClient(server, storage: storage),
          createHttpClient: (_) => http,
        );
        client.capture('evt');
        var flushed = false;
        client.flush().then((_) => flushed = true);
        async.elapse(const Duration(seconds: 10));

        expect(flushed, isTrue);
        async.elapse(const Duration(seconds: 30));
        expect(openCalls, 1,
            reason: 'a resend would store the events a second time');
        expect(getQueue(storage), isEmpty);
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
  Duration? connectionTimeout;

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledRequest implements HttpClientRequest {
  _ControlledRequest({HttpClientResponse? response, this.takeChunk})
      : _response = response ?? _ControlledResponse(Stream.value(<int>[]));

  final HttpClientResponse _response;

  /// How long the socket takes to accept each body chunk; immediate when
  /// null.
  final Future<void> Function()? takeChunk;
  int abortCalls = 0;
  int closeCalls = 0;
  int chunks = 0;

  @override
  final headers = _ControlledHeaders();

  @override
  bool followRedirects = true;

  @override
  int contentLength = -1;

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {
      await takeChunk?.call();
      chunks++;
    }
  }

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

/// A request whose body is several 64 KiB chunks once compressed: random
/// text does not compress much.
void _captureLargeEvent(DesktopPostHog client) {
  final random = Random(1);
  client.capture('large', properties: {
    'padding':
        base64.encode([for (var i = 0; i < 200000; i++) random.nextInt(256)]),
  });
}

class _ControlledResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _ControlledResponse(super.stream, {this.statusCode = HttpStatus.ok});

  @override
  final int statusCode;

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

const _ms = Duration(milliseconds: 1);
