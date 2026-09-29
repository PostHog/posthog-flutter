import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A request a client sent to the PostHog API.
class PostHogRequest {
  PostHogRequest._(this.path, this.headers, this.body);

  factory PostHogRequest._decode(
    String path,
    Map<String, String> headers,
    List<int> bytes,
  ) {
    if (bytes.isEmpty) return PostHogRequest._(path, headers, const {});
    final json = utf8.decode(
      headers['content-encoding'] == 'gzip' ? gzip.decode(bytes) : bytes,
    );
    return PostHogRequest._(
      path,
      headers,
      Map<String, Object?>.from(jsonDecode(json) as Map),
    );
  }

  /// The path of the endpoint, such as `/batch/` or `/flags/`.
  final String path;

  /// The headers, by lowercase name.
  final Map<String, String> headers;

  /// The JSON body, decompressed and decoded.
  final Map<String, Object?> body;

  bool get isBatch => path == '/batch/';

  bool get isFlags => path == '/flags/';

  /// The events of a `/batch/` request, oldest first.
  List<Map<String, Object?>> get events => [
        for (final event in body['batch']! as List)
          Map<String, Object?>.from(event as Map),
      ];

  /// The names of the events of a `/batch/` request, oldest first.
  List<Object?> get eventNames => [for (final event in events) event['event']];
}

/// How the PostHog API answers a request.
class PostHogResponse {
  const PostHogResponse(this.status,
      {this.body = '{"status": 1}', this.location, this.headers = const {}})
      : isDropped = false;

  /// A success with [json] as its body.
  PostHogResponse.json(Object? json)
      : this(HttpStatus.ok, body: jsonEncode(json));

  /// No answer: the connection is closed instead.
  const PostHogResponse.dropped()
      : status = 0,
        body = '',
        location = null,
        headers = const {},
        isDropped = true;

  final int status;
  final String body;

  /// Where a redirect points.
  final String? location;

  final Map<String, String> headers;

  final bool isDropped;
}

typedef PostHogResponder = FutureOr<PostHogResponse> Function(
  PostHogRequest request,
);

/// A fake of the PostHog API: records every request and answers it through
/// [respond].
abstract class PostHogApiFake {
  /// Answers the requests; a success by default. It may take its time, for
  /// a request that stays in flight.
  PostHogResponder respond = (_) => const PostHogResponse(HttpStatus.ok);

  /// The requests received, oldest first.
  final requests = <PostHogRequest>[];

  final _waiters = <({bool Function() isReady, Completer<void> done})>[];

  /// The host that reaches this API.
  String get url;

  /// Runs [create], so that the clients it creates send their requests to
  /// this API.
  T connect<T>(T Function() create);

  List<PostHogRequest> get batchRequests => [
        for (final request in requests)
          if (request.isBatch) request
      ];

  List<PostHogRequest> get flagsRequests => [
        for (final request in requests)
          if (request.isFlags) request
      ];

  /// Every event received, oldest first.
  List<Map<String, Object?>> get events =>
      [for (final request in batchRequests) ...request.events];

  List<Object?> get eventNames => [for (final event in events) event['event']];

  /// Completes with the first event named [name] once it has arrived.
  Future<Map<String, Object?>> waitForEvent(String name) async {
    await _waitUntil(() => events.any((event) => event['event'] == name));
    return events.firstWhere((event) => event['event'] == name);
  }

  /// Completes with the body of the `/flags/` request at [index] once it
  /// has arrived.
  Future<Map<String, Object?>> waitForFlagsRequest(int index) async {
    await _waitUntil(() => flagsRequests.length > index);
    return flagsRequests[index].body;
  }

  Future<PostHogResponse> _answer(PostHogRequest request) async {
    requests.add(request);
    _waiters.removeWhere((waiter) {
      if (!waiter.isReady()) return false;
      waiter.done.complete();
      return true;
    });
    return respond(request);
  }

  Future<void> _waitUntil(bool Function() isReady) {
    if (isReady()) return Future.value();
    final done = Completer<void>();
    _waiters.add((isReady: isReady, done: done));
    return done.future;
  }
}

/// The PostHog API on a local port.
class LocalPostHogServer extends PostHogApiFake {
  LocalPostHogServer._(this._server) : url = 'http://127.0.0.1:${_server.port}';

  final HttpServer _server;

  /// Where the server listens, also once it is closed.
  @override
  final String url;

  /// Starts a server, closed at the end of the test.
  static Future<LocalPostHogServer> start() async {
    final server = LocalPostHogServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._serve);
    addTearDown(server.close);
    return server;
  }

  @override
  T connect<T>(T Function() create) => create();

  /// The connections clients hold open to this server.
  int get openConnections => _server.connectionsInfo().total;

  /// Completes once the clients have closed every connection to this server.
  Future<void> connectionsClosed() async {
    // Real wait: the server learns about a closed socket asynchronously.
    for (var i = 0; openConnections > 0; i++) {
      if (i == 100) fail('the client kept $openConnections connection(s)');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    try {
      final bytes = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      final headers = <String, String>{};
      request.headers.forEach(
        (name, values) => headers[name] = values.join(', '),
      );
      final response = await _answer(
        PostHogRequest._decode(request.uri.path, headers, bytes),
      );
      if (response.isDropped) {
        (await request.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      request.response.statusCode = response.status;
      response.headers.forEach(request.response.headers.set);
      final location = response.location;
      if (location != null) {
        request.response.headers.set(HttpHeaders.locationHeader, location);
      }
      request.response.write(response.body);
      await request.response.close();
    } on IOException {
      // The client went away before the answer, as closing it makes it do.
    }
  }
}

/// A PostHog API that the clients created by [connect] reach without a
/// socket. For tests that control time with fake_async, which cannot wait
/// for a socket.
class InProcessPostHogApi extends PostHogApiFake {
  /// A host that never resolves: requests do not leave the process.
  @override
  String get url => 'http://posthog.invalid';

  @override
  T connect<T>(T Function() create) => HttpOverrides.runZoned(
        create,
        createHttpClient: (_) => _InProcessHttpClient(this),
      );
}

class _InProcessHttpClient implements HttpClient {
  _InProcessHttpClient(this._api);

  final PostHogApiFake _api;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _InProcessRequest(_api, url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InProcessRequest implements HttpClientRequest {
  _InProcessRequest(this._api, this.uri);

  final PostHogApiFake _api;
  final _body = <int>[];

  @override
  final Uri uri;

  @override
  final _InProcessHeaders headers = _InProcessHeaders();

  @override
  bool followRedirects = true;

  @override
  int contentLength = -1;

  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  Future<HttpClientResponse> close() async {
    final response = await _api._answer(
      PostHogRequest._decode(uri.path, headers.values, _body),
    );
    if (response.isDropped) {
      throw const HttpException(
        'Connection closed before full header was received',
      );
    }
    return _InProcessResponse(response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InProcessHeaders implements HttpHeaders {
  final values = <String, String>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InProcessResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _InProcessResponse(PostHogResponse response)
      : statusCode = response.status,
        super(Stream.value(utf8.encode(response.body))) {
    response.headers.forEach(headers.set);
  }

  @override
  final int statusCode;

  @override
  final _InProcessHeaders headers = _InProcessHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
