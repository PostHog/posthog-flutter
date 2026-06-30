// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/posthog_flutter_platform_interface.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';

const _adapterVersion = '1.0.0';
const _defaultFlushAt = 100;
const _defaultFlushIntervalMs = 500;
const _defaultMaxRetries = 3;

class ComplianceAdapter {
  ComplianceAdapter() : platform = _CompliancePlatform() {
    PosthogFlutterPlatformInterface.instance = platform;
  }

  final _CompliancePlatform platform;
  HttpServer? _server;

  Future<HttpServer> start({int port = 8080}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    unawaited(_serve(server));
    return server;
  }

  Future<void> close() async {
    await platform.resetAdapterState();
    await _server?.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _route(request);
      } catch (error, stackTrace) {
        stderr.writeln('Unhandled adapter error: $error\n$stackTrace');
        await _sendJson(request, {'error': error.toString()}, statusCode: 500);
      }
    }
  }

  Future<void> _route(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    if (method == 'GET' && path == '/health') {
      await _sendJson(request, {
        'sdk_name': postHogFlutterSdkName,
        'sdk_version': postHogFlutterVersion,
        'adapter_version': _adapterVersion,
        'capabilities': ['capture_v0', 'encoding_gzip'],
      });
      return;
    }

    if (method == 'POST' && path == '/init') {
      final body = await _readJson(request);
      final apiKey = body['api_key'] as String?;
      final host = body['host'] as String?;
      if (apiKey == null || apiKey.isEmpty) {
        await _sendJson(request, {'error': 'api_key is required'},
            statusCode: 400);
        return;
      }
      if (host == null || host.isEmpty) {
        await _sendJson(request, {'error': 'host is required'},
            statusCode: 400);
        return;
      }

      final flushAt = _readInt(body['flush_at']) ?? _defaultFlushAt;
      final flushIntervalMs =
          _readInt(body['flush_interval_ms']) ?? _defaultFlushIntervalMs;
      final maxRetries = _readInt(body['max_retries']) ?? _defaultMaxRetries;
      final enableCompression = body['enable_compression'] == true;

      await platform.resetAdapterState();
      platform.configure(
        apiKey: apiKey,
        host: host,
        flushAt: flushAt,
        flushIntervalMs: flushIntervalMs,
        maxRetries: maxRetries,
        enableCompression: enableCompression,
      );

      final config = PostHogConfig(apiKey)
        ..host = host
        ..flushAt = flushAt
        ..flushInterval = Duration(milliseconds: flushIntervalMs)
        ..preloadFeatureFlags = false
        ..captureApplicationLifecycleEvents = false
        ..debug = true;
      await Posthog().setup(config);

      await _sendJson(request, {'success': true});
      return;
    }

    if (method == 'POST' && path == '/capture') {
      if (!platform.isInitialized) {
        await _sendJson(
          request,
          {'error': 'SDK not initialized'},
          statusCode: 400,
        );
        return;
      }

      final body = await _readJson(request);
      final distinctId = body['distinct_id'] as String?;
      final event = body['event'] as String?;
      if (distinctId == null || distinctId.isEmpty) {
        await _sendJson(
          request,
          {'error': 'distinct_id is required'},
          statusCode: 400,
        );
        return;
      }
      if (event == null || event.isEmpty) {
        await _sendJson(request, {'error': 'event is required'},
            statusCode: 400);
        return;
      }

      final properties = _readObjectMap(body['properties']);
      final timestamp = body['timestamp'] as String?;
      platform.stageCapture(distinctId: distinctId, timestamp: timestamp);
      await Posthog().capture(eventName: event, properties: properties);

      await _sendJson(request, {
        'success': true,
        'uuid': platform.lastCapturedUuid,
      });
      return;
    }

    if (method == 'POST' && path == '/get_feature_flag') {
      if (!platform.isInitialized) {
        await _sendJson(
          request,
          {'error': 'SDK not initialized'},
          statusCode: 400,
        );
        return;
      }

      final body = await _readJson(request);
      final key = body['key'] as String?;
      final distinctId = body['distinct_id'] as String?;
      if (key == null || key.isEmpty) {
        await _sendJson(request, {'error': 'key is required'}, statusCode: 400);
        return;
      }
      if (distinctId == null || distinctId.isEmpty) {
        await _sendJson(
          request,
          {'error': 'distinct_id is required'},
          statusCode: 400,
        );
        return;
      }

      final value = await platform.evaluateFeatureFlag(
        key: key,
        distinctId: distinctId,
        personProperties: _readNullableObjectMap(body['person_properties']),
        groups: _readNullableObjectMap(body['groups']),
        groupProperties: _readNestedObjectMap(body['group_properties']),
        disableGeoip: body['disable_geoip'] == true,
      );

      await _sendJson(request, {'success': true, 'value': value});
      return;
    }

    if (method == 'POST' && path == '/flush') {
      if (!platform.isInitialized) {
        await _sendJson(
          request,
          {'error': 'SDK not initialized'},
          statusCode: 400,
        );
        return;
      }

      await platform.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _sendJson(request, {
        'success': true,
        'events_flushed': platform.state.totalEventsSent,
      });
      return;
    }

    if (method == 'GET' && path == '/state') {
      await _sendJson(request, platform.state.toJson());
      return;
    }

    if (method == 'POST' && path == '/reset') {
      await platform.resetAdapterState();
      await _sendJson(request, {'success': true});
      return;
    }

    await _sendJson(request, {'error': 'not found'}, statusCode: 404);
  }
}

class _CompliancePlatform extends PosthogFlutterPlatformInterface {
  _AdapterState state = _AdapterState();
  final _random = Random.secure();

  String? _apiKey;
  String? _host;
  int _flushAt = _defaultFlushAt;
  int _flushIntervalMs = _defaultFlushIntervalMs;
  int _maxRetries = _defaultMaxRetries;
  bool _enableCompression = false;
  bool _autoFlushPaused = false;
  Timer? _flushTimer;
  Future<void>? _activeFlush;
  String? _nextDistinctId;
  String? _nextTimestamp;

  bool get isInitialized => _apiKey != null && _host != null;
  String? lastCapturedUuid;

  void configure({
    required String apiKey,
    required String host,
    required int flushAt,
    required int flushIntervalMs,
    required int maxRetries,
    required bool enableCompression,
  }) {
    _apiKey = apiKey;
    _host = host;
    _flushAt = max(1, flushAt);
    _flushIntervalMs = max(1, flushIntervalMs);
    _maxRetries = max(0, maxRetries);
    _enableCompression = enableCompression;
    _autoFlushPaused = false;
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      Duration(milliseconds: _flushIntervalMs),
      (_) => unawaited(_flushFromTimer()),
    );
  }

  void stageCapture({required String distinctId, String? timestamp}) {
    _nextDistinctId = distinctId;
    _nextTimestamp = timestamp;
  }

  @override
  Future<void> setup(PostHogConfig config) async {}

  @override
  Future<void> reset() => resetAdapterState();

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    if (!isInitialized) {
      throw StateError('SDK not initialized');
    }

    final distinctId = _nextDistinctId;
    if (distinctId == null || distinctId.isEmpty) {
      throw StateError('distinct_id was not staged by the adapter');
    }

    final timestamp = _nextTimestamp;
    _nextDistinctId = null;
    _nextTimestamp = null;

    final uuid = _uuidV4();
    lastCapturedUuid = uuid;

    final eventProperties = <String, Object?>{
      ...?properties,
      'distinct_id': distinctId,
      'token': _apiKey,
      '\$lib': postHogFlutterSdkName,
      '\$lib_version': postHogFlutterVersion,
      if (userProperties != null && userProperties.isNotEmpty)
        '\$set': userProperties,
      if (userPropertiesSetOnce != null && userPropertiesSetOnce.isNotEmpty)
        '\$set_once': userPropertiesSetOnce,
    };

    _autoFlushPaused = false;
    state.queue.add({
      'uuid': uuid,
      'event': eventName,
      'distinct_id': distinctId,
      'properties': eventProperties,
      'timestamp': timestamp ?? DateTime.now().toUtc().toIso8601String(),
    });
    state.totalEventsCaptured++;
    state.pendingEvents = state.queue.length;

    if (state.queue.length >= _flushAt) {
      unawaited(flush());
    }
  }

  Future<void> _flushFromTimer() {
    if (_autoFlushPaused) {
      return Future.value();
    }
    return flush();
  }

  @override
  Future<void> flush() {
    final activeFlush = _activeFlush;
    if (activeFlush != null) {
      return activeFlush;
    }

    final flushFuture = _flushInternal();
    _activeFlush = flushFuture;
    return flushFuture.whenComplete(() {
      if (identical(_activeFlush, flushFuture)) {
        _activeFlush = null;
      }
    });
  }

  Future<void> _flushInternal() async {
    final flushState = state;
    final apiKey = _apiKey;
    final host = _host;
    final maxRetries = _maxRetries;
    final enableCompression = _enableCompression;
    if (apiKey == null || host == null || flushState.queue.isEmpty) {
      return;
    }

    final batch = List<Map<String, Object?>>.from(flushState.queue);
    final success = await _sendBatchWithRetries(
      flushState,
      batch,
      apiKey: apiKey,
      host: host,
      maxRetries: maxRetries,
      enableCompression: enableCompression,
    );
    if (success) {
      final sentUuids = batch.map((event) => event['uuid']).toSet();
      flushState.queue
          .removeWhere((event) => sentUuids.contains(event['uuid']));
      flushState.pendingEvents = flushState.queue.length;
      flushState.totalEventsSent += batch.length;
      if (identical(state, flushState)) {
        _autoFlushPaused = false;
      }
    } else {
      flushState.pendingEvents = flushState.queue.length;
      if (identical(state, flushState)) {
        _autoFlushPaused = true;
      }
    }
  }

  Future<bool> _sendBatchWithRetries(
    _AdapterState flushState,
    List<Map<String, Object?>> batch, {
    required String apiKey,
    required String host,
    required int maxRetries,
    required bool enableCompression,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final result = await _postBatch(
        flushState,
        batch,
        attempt,
        apiKey: apiKey,
        host: host,
        enableCompression: enableCompression,
      );
      flushState.requestsMade.add(_RequestRecord(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        statusCode: result.statusCode,
        retryAttempt: attempt,
        eventCount: batch.length,
        uuidList: batch.map((event) => event['uuid']! as String).toList(),
      ));

      if (attempt > 0) {
        flushState.totalRetries++;
      }

      if (result.statusCode >= 200 && result.statusCode < 300) {
        return true;
      }

      flushState.lastError =
          'Batch request failed with HTTP ${result.statusCode}';
      if (attempt < maxRetries && _shouldRetry(result.statusCode)) {
        await Future<void>.delayed(
          Duration(milliseconds: result.retryAfterMs ?? 100),
        );
        continue;
      }
      return false;
    }
    return false;
  }

  bool _shouldRetry(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  Future<_PostResult> _postBatch(
    _AdapterState flushState,
    List<Map<String, Object?>> batch,
    int attempt, {
    required String apiKey,
    required String host,
    required bool enableCompression,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(host).resolve(
        attempt > 0 ? '/batch?retry_count=$attempt' : '/batch',
      );
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        '$postHogFlutterSdkName/$postHogFlutterVersion',
      );

      final payload = jsonEncode({
        'api_key': apiKey,
        'batch': batch,
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      });
      final body = utf8.encode(payload);
      final bytesToSend = enableCompression ? gzip.encode(body) : body;
      if (enableCompression) {
        request.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      }
      request.contentLength = bytesToSend.length;
      request.add(bytesToSend);

      final response = await request.close();
      final retryAfterMs = _retryAfterMs(response.headers);
      await response.drain<void>();
      return _PostResult(response.statusCode, retryAfterMs: retryAfterMs);
    } catch (error) {
      flushState.lastError = error.toString();
      return const _PostResult(500);
    } finally {
      client.close(force: true);
    }
  }

  Future<Object?> evaluateFeatureFlag({
    required String key,
    required String distinctId,
    Map<String, Object?>? personProperties,
    Map<String, Object?>? groups,
    Map<String, Map<String, Object?>>? groupProperties,
    required bool disableGeoip,
  }) async {
    final payload = <String, Object?>{
      'api_key': _apiKey,
      'distinct_id': distinctId,
      'person_properties': <String, Object?>{
        ...?personProperties,
        'distinct_id': distinctId,
      },
      'groups': groups ?? <String, Object?>{},
      'group_properties': groupProperties ?? <String, Map<String, Object?>>{},
      'geoip_disable': disableGeoip,
      'flag_keys_to_evaluate': [key],
    };

    final client = HttpClient();
    Object? value = false;
    try {
      final uri = Uri.parse(_host!).resolve('/flags/?v=2');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        state.lastError =
            'Feature flag request failed with HTTP ${response.statusCode}';
        throw HttpException(state.lastError!, uri: uri);
      }
      final decoded = body.isEmpty ? null : jsonDecode(body);
      if (decoded is Map) {
        final flags = decoded['featureFlags'] ?? decoded['flags'];
        if (flags is Map && flags.containsKey(key)) {
          value = flags[key];
        }
      }
    } finally {
      client.close(force: true);
    }

    state.queue.add({
      'uuid': _uuidV4(),
      'event': r'$feature_flag_called',
      'distinct_id': distinctId,
      'properties': <String, Object?>{
        'distinct_id': distinctId,
        'token': _apiKey,
        r'$lib': postHogFlutterSdkName,
        r'$lib_version': postHogFlutterVersion,
        r'$feature_flag': key,
        r'$feature_flag_response': value,
        r'$feature/' + key: value,
      },
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    state.totalEventsCaptured++;
    state.pendingEvents = state.queue.length;

    return value;
  }

  int? _retryAfterMs(HttpHeaders headers) {
    final value = headers.value(HttpHeaders.retryAfterHeader);
    if (value == null) {
      return null;
    }
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return seconds * 1000;
    }
    final date = HttpDate.parse(value);
    return date
        .difference(DateTime.now().toUtc())
        .inMilliseconds
        .clamp(0, 60000);
  }

  Future<void> resetAdapterState() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _activeFlush = null;
    _autoFlushPaused = false;
    _apiKey = null;
    _host = null;
    _nextDistinctId = null;
    _nextTimestamp = null;
    lastCapturedUuid = null;
    state = _AdapterState();
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}

class _AdapterState {
  int pendingEvents = 0;
  int totalEventsCaptured = 0;
  int totalEventsSent = 0;
  int totalRetries = 0;
  String? lastError;
  final queue = <Map<String, Object?>>[];
  final requestsMade = <_RequestRecord>[];

  Map<String, Object?> toJson() => {
        'pending_events': pendingEvents,
        'total_events_captured': totalEventsCaptured,
        'total_events_sent': totalEventsSent,
        'total_retries': totalRetries,
        'last_error': lastError,
        'requests_made':
            requestsMade.map((request) => request.toJson()).toList(),
      };
}

class _PostResult {
  const _PostResult(this.statusCode, {this.retryAfterMs});

  final int statusCode;
  final int? retryAfterMs;
}

class _RequestRecord {
  _RequestRecord({
    required this.timestampMs,
    required this.statusCode,
    required this.retryAttempt,
    required this.eventCount,
    required this.uuidList,
  });

  final int timestampMs;
  final int statusCode;
  final int retryAttempt;
  final int eventCount;
  final List<String> uuidList;

  Map<String, Object?> toJson() => {
        'timestamp_ms': timestampMs,
        'status_code': statusCode,
        'retry_attempt': retryAttempt,
        'event_count': eventCount,
        'uuid_list': uuidList,
      };
}

Future<Map<String, Object?>> _readJson(HttpRequest request) async {
  final rawBody = await utf8.decoder.bind(request).join();
  if (rawBody.trim().isEmpty) {
    return <String, Object?>{};
  }
  final decoded = jsonDecode(rawBody);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  return Map<String, Object?>.from(decoded as Map);
}

Map<String, Object>? _readObjectMap(Object? value) {
  final map = _readNullableObjectMap(value);
  return map?.cast<String, Object>();
}

Map<String, Object?>? _readNullableObjectMap(Object? value) {
  if (value == null) {
    return null;
  }
  return Map<String, Object?>.from(value as Map);
}

Map<String, Map<String, Object?>>? _readNestedObjectMap(Object? value) {
  if (value == null) {
    return null;
  }
  final source = Map<String, Object?>.from(value as Map);
  return source.map(
    (key, nested) => MapEntry(
      key,
      nested == null
          ? <String, Object?>{}
          : Map<String, Object?>.from(nested as Map),
    ),
  );
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

Future<void> _sendJson(
  HttpRequest request,
  Object value, {
  int statusCode = 200,
}) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(value));
  await request.response.close();
}
