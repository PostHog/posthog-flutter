import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Forwards bytes once, without retrying or changing SDK bodies or responses.
class WireObserver {
  HttpServer? _server;
  final HttpClient _client = HttpClient()..autoUncompress = false;
  Uri? target;
  final List<Map<String, Object?>> requests = [];
  final Map<String, int> _expected = {};
  final Map<String, String> _completed = {};
  final Set<String> _outstanding = {};
  Object? _observationError;
  int _active = 0;
  int _generation = 0;
  DateTime _lastActivity = DateTime.now();

  String get url => 'http://127.0.0.1:${_server!.port}/run-$_generation';

  Future<void> start(int port) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) => unawaited(_forward(request)));
  }

  void expectCapture(String event) {
    _expected.update(event, (count) => count + 1, ifAbsent: () => 1);
  }

  void reset() {
    _generation++;
    _observationError = null;
    target = null;
    requests.clear();
    _expected.clear();
    _completed.clear();
    _outstanding.clear();
    _lastActivity = DateTime.now();
  }

  Future<void> close() async {
    _client.close(force: true);
    await _server?.close(force: true);
  }

  Future<void> waitForObservedCaptures() async {
    if (_expected.isEmpty) {
      throw UnsupportedError('No submitted capture completion can be observed; '
          'Flutter does not expose an empty-queue or automatic-event drain signal');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    // Allow the native queue to dispatch after the MethodChannel reply.
    final started = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      if (_observationError != null) {
        throw StateError('Wire observation failed: $_observationError');
      }
      final counts = <String, int>{};
      for (final event in _completed.values) {
        counts.update(event, (count) => count + 1, ifAbsent: () => 1);
      }
      if (_expected.entries.every((e) => (counts[e.key] ?? 0) >= e.value) &&
          _outstanding.isEmpty &&
          _active == 0 &&
          DateTime.now().difference(_lastActivity).inMilliseconds >= 1000 &&
          DateTime.now().difference(started).inMilliseconds >= 1000) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException(
      'Native wire completion was not observed within 30s; '
      'no additional flush or retry was initiated by the adapter',
    );
  }

  Future<void> _forward(HttpRequest incoming) async {
    final generation = _generation;
    final destination = target;
    _active++;
    _lastActivity = DateTime.now();
    try {
      final prefix = '/run-$generation/';
      if (destination == null || !incoming.uri.path.startsWith(prefix)) {
        // A closed SDK can finish old asynchronous work. Never send it to the
        // next test's mock configuration.
        incoming.response.statusCode = HttpStatus.gone;
        return;
      }
      final forwardedUri = incoming.uri.replace(
        path: incoming.uri.path.substring(prefix.length - 1),
      );
      final bytes = await incoming.fold<List<int>>(
        [],
        (b, chunk) => b..addAll(chunk),
      );
      final outgoing = await _client.openUrl(
        incoming.method,
        destination.resolve(forwardedUri.toString()),
      );
      outgoing.followRedirects = false;
      incoming.headers.forEach((name, values) {
        if (!_hopHeaders.contains(name)) outgoing.headers.set(name, values);
      });
      outgoing.add(bytes);
      final response = await outgoing.close();
      final responseBytes = await response.fold<List<int>>(
        [],
        (b, chunk) => b..addAll(chunk),
      );
      if (generation == _generation) {
        final record = <String, Object?>{
          'method': incoming.method,
          'path': forwardedUri.toString(),
          'status_code': response.statusCode,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'body_base64': base64Encode(bytes),
          'content_encoding': incoming.headers.value('content-encoding'),
        };
        requests.add(record);
        try {
          if (forwardedUri.path.startsWith('/batch')) {
            final decodedBytes =
                incoming.headers.value('content-encoding') == 'gzip'
                    ? gzip.decode(bytes)
                    : bytes;
            final body = jsonDecode(utf8.decode(decodedBytes)) as Map;
            final batch = body['batch'] as List;
            final status = response.statusCode;
            final terminal = (status >= 200 && status < 300) ||
                (status >= 400 &&
                    status < 500 &&
                    status != 408 &&
                    status != 429 &&
                    (status != 413 || batch.length == 1));
            for (final event in batch.cast<Map>()) {
              final uuid = event['uuid'] as String;
              if (terminal) {
                _completed[uuid] = event['event'] as String;
                _outstanding.remove(uuid);
              } else {
                _outstanding.add(uuid);
              }
            }
          }
        } catch (error) {
          // Observation errors must never change the response delivered to the SDK.
          _observationError = error;
        }
      }
      incoming.response.statusCode = response.statusCode;
      response.headers.forEach((name, values) {
        if (!_hopHeaders.contains(name))
          incoming.response.headers.set(name, values);
      });
      incoming.response.add(responseBytes);
    } catch (error) {
      stderr.writeln('Wire observer failed: $error');
      incoming.response.statusCode = HttpStatus.badGateway;
    } finally {
      await incoming.response.close();
      _active--;
      _lastActivity = DateTime.now();
    }
  }
}

const _hopHeaders = {
  'host',
  'connection',
  'content-length',
  'transfer-encoding',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'upgrade',
};
