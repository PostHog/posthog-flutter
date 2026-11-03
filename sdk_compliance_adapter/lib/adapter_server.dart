// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/core/capture_v1.dart';
import 'package:posthog_flutter/src/core/feature_flags.dart';
import 'package:posthog_flutter/src/core/file_storage.dart';
import 'package:posthog_flutter/src/core/persistence.dart';
import 'package:posthog_flutter/src/core/posthog_core.dart';
import 'package:posthog_flutter/src/posthog_desktop_app_info.dart';
import 'package:posthog_flutter/src/posthog_desktop_client.dart';
import 'package:posthog_flutter/src/posthog_flutter_desktop.dart';
import 'package:posthog_flutter/src/posthog_flutter_version.dart';
import 'package:posthog_flutter/src/utils/project_token.dart';

const _adapterVersion = '1.0.0';
const _defaultFlushAt = 100;
const _defaultFlushIntervalMs = 500;
// The longest the SDK waits on any lane; it gives up on shorter lanes itself.
const _upstreamTimeout = captureAiDefaultTimeout;

class ComplianceAdapter {
  final _CompliancePlatform platform = _CompliancePlatform();
  HttpServer? _server;
  DebugPrintCallback? _debugPrint;

  Future<HttpServer> start({int port = 8080}) async {
    final debugPrintBefore = _debugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) platform.state.logLines.add(message);
      debugPrintBefore(message, wrapWidth: wrapWidth);
    };
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    unawaited(_serve(server));
    return server;
  }

  Future<void> close() async {
    await platform.resetAdapterState();
    await _server?.close(force: true);
    if (_debugPrint case final restored?) debugPrint = restored;
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
        'capabilities': [
          'capture_v1',
          'capture_ai_v1',
          'encoding_gzip',
          'event_options',
          'fail_open',
          'generated_payloads',
          'log_capture',
          'property_layers',
        ],
      });
      return;
    }

    if (method == 'POST' && path == '/init') {
      final body = await _readJson(request);
      final apiKey = body['api_key'] as String?;
      final host = body['host'] as String?;
      if (apiKey == null) {
        await _sendJson(
            request,
            {
              'error': 'api_key is required',
            },
            statusCode: 400);
        return;
      }
      if (host == null || host.isEmpty) {
        await _sendJson(
            request,
            {
              'error': 'host is required',
            },
            statusCode: 400);
        return;
      }

      final flushAt = _readInt(body['flush_at']) ?? _defaultFlushAt;
      final flushIntervalMs =
          _readInt(body['flush_interval_ms']) ?? _defaultFlushIntervalMs;
      final enableCompression = body['enable_compression'] == true;

      final compression =
          enableCompression ? PostHogCompression.gzip : PostHogCompression.none;
      final config = PostHogConfig(apiKey)
        ..flushAt = flushAt
        ..flushInterval = Duration(milliseconds: flushIntervalMs)
        ..compression = compression
        ..captureAiCompression = compression
        ..preloadFeatureFlags = false
        ..captureApplicationLifecycleEvents = false
        ..debug = true;

      final bootstrap = _readNullableObjectMap(body['bootstrap']);
      if (bootstrap != null) {
        config.bootstrap = PostHogBootstrapConfig(
          distinctId: bootstrap['distinct_id'] as String?,
          isIdentifiedId: bootstrap['is_identified_id'] == true,
          featureFlags: _readObjectMap(bootstrap['feature_flags']),
          featureFlagPayloads: _readNullableObjectMap(
            bootstrap['feature_flag_payloads'],
          ),
        );
      }

      final beforeSend = _readNullableObjectMap(body['before_send']);
      final setProperties =
          _readObjectMap(beforeSend?['set_properties']) ?? const {};
      if (beforeSend != null) {
        config.beforeSend = [
          (event) =>
              event..properties = {...?event.properties, ...setProperties},
        ];
      }

      await platform.resetAdapterState();
      if (isUsableProjectToken(config.projectToken)) {
        await platform.configure(
          config,
          host: host,
          superProperties: _readNullableObjectMap(body['super_properties']),
        );
      } else {
        platform.disable();
      }

      await _sendJson(request, {'success': true});
      return;
    }

    if (method == 'POST' && (path == '/capture' || path == '/capture_ai')) {
      if (!platform.isInitialized) {
        await _sendJson(
            request,
            {
              'error': 'SDK not initialized',
            },
            statusCode: 400);
        return;
      }

      final body = await _readJson(request);
      final distinctId = body['distinct_id'] as String?;
      final event = body['event'] as String?;
      if (distinctId == null || distinctId.isEmpty) {
        await _sendJson(
            request,
            {
              'error': 'distinct_id is required',
            },
            statusCode: 400);
        return;
      }
      if (event == null || event.isEmpty) {
        await _sendJson(
            request,
            {
              'error': 'event is required',
            },
            statusCode: 400);
        return;
      }

      final properties = _readNullableObjectMap(body['properties']) ?? {};
      final padToBytes = _readInt(body['pad_properties_to_bytes']);
      final uuid = await platform.capture(
        distinctId: distinctId,
        event: event,
        properties: padToBytes == null
            ? properties
            : _padProperties(properties, padToBytes, body['marker'] as String?),
        options: _readNullableObjectMap(body['options']),
        timestamp: body['timestamp'] as String?,
        ai: path == '/capture_ai',
      );

      await _sendJson(request, {'success': true, 'uuid': uuid});
      return;
    }

    if (method == 'POST' && path == '/get_feature_flag') {
      if (!platform.isInitialized) {
        await _sendJson(
            request,
            {
              'error': 'SDK not initialized',
            },
            statusCode: 400);
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
            {
              'error': 'distinct_id is required',
            },
            statusCode: 400);
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
            {
              'error': 'SDK not initialized',
            },
            statusCode: 400);
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
      await _sendJson(request, platform.stateJson());
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

/// The real client, run by the real desktop plugin, so the harness tests the
/// SDK's own event building, beforeSend, queue, flags and requests. The
/// harness sends a distinct id and a timestamp per call, which the plugin's
/// capture() doesn't take: the id would need identify(), which adds
/// `$identify` events to the batches the suites count.
class _CaptureClient extends DesktopPostHog {
  _CaptureClient(PostHogConfig config, FileStorage storage)
      : super(
          config,
          storage: storage,
          staticContext: const {},
          timezone: null,
        );

  String? nextTimestamp;
  String? lastUuid;
  Map<String, Object?> _flagsRequestFields = const {};
  String? _flagsUser;
  bool _switchingFlagsUser = false;
  void Function()? onCaptured;

  @override
  ({String uuid, Future<bool> queued}) captureStateless(
    String distinctId,
    String event, {
    required Map<String, Object?> properties,
    Map<String, Object?>? options,
    String? timestamp,
  }) {
    final queued = super.captureStateless(
      distinctId,
      event,
      properties: properties,
      options: options,
      timestamp: timestamp,
    );
    onCaptured?.call();
    return queued;
  }

  @override
  Future<String?> captureAiStateless(
    String distinctId,
    String event, {
    required Map<String, Object?> properties,
    Map<String, Object?>? options,
    String? timestamp,
  }) async {
    final uuid = await super.captureAiStateless(
      distinctId,
      event,
      properties: properties,
      options: options,
      timestamp: timestamp,
    );
    if (uuid != null) onCaptured?.call();
    return uuid;
  }

  void _actAs(String distinctId) {
    setPersistedProperty(PostHogPersistedProperty.distinctId, distinctId);
    setPersistedProperty(PostHogPersistedProperty.personMode, 'identified');
  }

  @override
  PostHogPreparedEvent? prepareEvent(
    String event, {
    Map<String, Object?>? properties,
    Map<String, Object?>? options,
  }) {
    final prepared =
        super.prepareEvent(event, properties: properties, options: options);
    final timestamp = nextTimestamp;
    if (prepared == null || timestamp == null) return prepared;
    return (
      properties: prepared.properties,
      options: prepared.options,
      timestamp: timestamp,
    );
  }

  @override
  Future<String?> capturePrepared(
    String event,
    PostHogPreparedEvent prepared,
  ) =>
      super.capturePrepared(event, prepared).then((uuid) => lastUuid = uuid);

  Future<PostHogFeatureFlagResult?> evaluateFlag(
    String key, {
    required String distinctId,
    required Map<String, Object?> personProperties,
    required Map<String, Object?> groups,
    required Map<String, Map<String, Object?>> groupProperties,
    required bool disableGeoip,
  }) async {
    // A user's cached flags and reported flag calls must not serve the next.
    if (_flagsUser != null && _flagsUser != distinctId) {
      _switchingFlagsUser = true;
      reset();
      _switchingFlagsUser = false;
    }
    _flagsUser = distinctId;
    _actAs(distinctId);
    if (groups.isEmpty) {
      unregister(r'$groups');
    } else {
      register({r'$groups': groups});
    }
    resetPersonPropertiesForFlags();
    setPersonPropertiesForFlags(personProperties);
    resetGroupPropertiesForFlags();
    setGroupPropertiesForFlags(groupProperties);
    _flagsRequestFields = {
      'geoip_disable': disableGeoip,
      'flag_keys_to_evaluate': [key],
    };
    await reloadFeatureFlagsAsync();
    return getFeatureFlagResult(key, sendEvent: true);
  }

  // The harness tests these server-SDK fields, which the client doesn't send.
  @override
  Future<GetFlagsResult> getFlags(
    String distinctId, {
    required Map<String, Object> groups,
    required Map<String, Object?> personProperties,
    required Map<String, Map<String, Object?>> groupProperties,
    required Map<String, Object?> extraPayload,
  }) {
    // reset() reloads for an anonymous id nobody asked about. Its answer could
    // outlive a failed reload for the requested user, so no request is sent.
    if (_switchingFlagsUser) {
      return Future.value(GetFlagsFailure(const FeatureFlagRequestError(
          type: FeatureFlagRequestErrorType.unknownError)));
    }
    return super.getFlags(
      distinctId,
      groups: groups,
      personProperties: personProperties,
      groupProperties: groupProperties,
      extraPayload: {...extraPayload, ..._flagsRequestFields},
    );
  }

  @override
  int get queuedEventCount => super.queuedEventCount;

  void Function() onSent(void Function(int count) listener) =>
      events.on('flush', (sent) => listener((sent! as List).length));

  void Function() onError(void Function(Object error) listener) =>
      events.on('error', (error) => listener(error!));
}

/// Forwards the SDK's capture requests to the harness and records them for
/// `/state`: the SDK doesn't expose what it sent.
class _RecordingProxy {
  _RecordingProxy._(this._server, this._target, this._state);

  final HttpServer _server;
  final Uri _target;
  final _AdapterState _state;
  final _client = HttpClient()..autoUncompress = false;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_RecordingProxy> start(String host, _AdapterState state) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _RecordingProxy._(server, Uri.parse(host), state);
    unawaited(proxy._serve());
    return proxy;
  }

  Future<void> close() async {
    _client.close(force: true);
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      unawaited(_forward(request));
    }
  }

  Future<void> _forward(HttpRequest request) async {
    final response = request.response;
    var headersSent = false;
    try {
      final body = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      final upstream = await _client.openUrl(
        request.method,
        _target.replace(
          path: request.uri.path,
          query: request.uri.hasQuery ? request.uri.query : null,
        ),
      );
      request.headers.forEach((name, values) {
        if (name != HttpHeaders.hostHeader &&
            name != HttpHeaders.contentLengthHeader) {
          upstream.headers.set(name, values);
        }
      });
      // Redirects are the SDK's to follow or refuse.
      upstream.followRedirects = false;
      upstream.contentLength = body.length;
      upstream.add(body);
      final result = await upstream.close().timeout(
        _upstreamTimeout,
        onTimeout: () {
          upstream.abort();
          throw TimeoutException('No response from the harness');
        },
      );
      _record(request, body, result.statusCode);

      response.statusCode = result.statusCode;
      result.headers.forEach((name, values) {
        if (name == HttpHeaders.locationHeader) {
          response.headers.set(name, values.map(_proxyLocation).toList());
        } else if (name != HttpHeaders.contentLengthHeader &&
            name != HttpHeaders.transferEncodingHeader) {
          response.headers.set(name, values);
        }
      });
      headersSent = true;
      // Not addStream: a failing body would take the response down with it.
      await for (final chunk in result) {
        response.add(chunk);
      }
    } catch (error) {
      _state.lastError = error.toString();
      // After the headers the status stands: the SDK drops a 2xx whose body
      // fails for good, so it must not turn into a retry here.
      if (!headersSent) response.statusCode = HttpStatus.badGateway;
    }
    await response.close();
  }

  /// The SDK only follows a redirect within the origin it was configured
  /// with, which is this proxy's and not the harness's.
  String _proxyLocation(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null ||
        uri.scheme != _target.scheme ||
        uri.host != _target.host ||
        uri.port != _target.port) {
      return location;
    }
    return uri.replace(host: '127.0.0.1', port: _server.port).toString();
  }

  void _record(HttpRequest request, List<int> body, int statusCode) {
    if (request.uri.path != captureV1Path &&
        request.uri.path != captureV1AiPath) {
      return;
    }
    final gzipped =
        request.headers.value(HttpHeaders.contentEncodingHeader) == 'gzip';
    final decoded =
        jsonDecode(utf8.decode(gzipped ? gzip.decode(body) : body)) as Map;
    final batch = decoded['batch'] as List;
    final attempt =
        int.tryParse(request.headers.value('PostHog-Attempt') ?? '') ?? 1;
    if (attempt > 1) _state.totalRetries++;
    if (statusCode < 200 || statusCode >= 300) {
      _state.lastError = 'Capture request failed with HTTP $statusCode';
    }
    _state.requestsMade.add(
      _RequestRecord(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        statusCode: statusCode,
        retryAttempt: attempt - 1,
        eventCount: batch.length,
        uuidList: [for (final event in batch) (event as Map)['uuid'] as String],
      ),
    );
  }
}

class _CompliancePlatform {
  _AdapterState state = _AdapterState();

  PosthogFlutterDesktop? _plugin;
  _CaptureClient? _client;
  _RecordingProxy? _proxy;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Initialized as an app whose setup was skipped: every call is a no-op.
  void disable() => _initialized = true;

  Future<void> configure(
    PostHogConfig config, {
    required String host,
    Map<String, Object?>? superProperties,
  }) async {
    final proxy = await _RecordingProxy.start(host, state);
    config.host = proxy.url;
    _CaptureClient? created;
    final plugin = PosthogFlutterDesktop(
      appDirectory: () async => null,
      appInfo: const DesktopAppInfo(),
      timezone: null,
      // No OS or app context: the suites expect exact property sets.
      createClient: (config, storage, _) =>
          created = _CaptureClient(config, storage),
    );
    await plugin.setup(config);
    final client = created;
    if (client == null) {
      await proxy.close();
      throw StateError('The plugin did not start a client');
    }
    final clientState = state;
    client.onCaptured = () => clientState.totalEventsCaptured++;
    client.onSent((count) => clientState.totalEventsSent += count);
    client.onError((error) => clientState.lastError = error.toString());
    if (superProperties != null) client.register(superProperties);
    _proxy = proxy;
    _plugin = plugin;
    _client = client;
    _initialized = true;
  }

  Future<String?> capture({
    required String distinctId,
    required String event,
    required Map<String, Object?> properties,
    Map<String, Object?>? options,
    String? timestamp,
    bool ai = false,
  }) async {
    final plugin = _plugin;
    final client = _client;
    if (plugin == null || client == null) return null;
    client._actAs(distinctId);
    client.nextTimestamp =
        DateTime.tryParse(timestamp ?? '')?.toUtc().toIso8601String();
    client.lastUuid = null;
    final nonNull = {
      for (final MapEntry(:key, :value) in properties.entries)
        if (value != null) key: value,
    };
    try {
      if (ai) {
        return await plugin.captureAi(
          eventName: event,
          properties: nonNull,
          options: options,
        );
      }
      await plugin.capture(
        eventName: event,
        properties: nonNull,
        options: options,
      );
      return client.lastUuid;
    } finally {
      client.nextTimestamp = null;
    }
  }

  Map<String, Object?> stateJson() =>
      state.toJson(pendingEvents: _client?.queuedEventCount ?? 0);

  Future<void> flush() async {
    try {
      await _client?.flush();
    } catch (error) {
      state.lastError = error.toString();
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
    final client = _client;
    if (client == null) return false;
    final result = await client.evaluateFlag(
      key,
      distinctId: distinctId,
      personProperties: personProperties ?? const {},
      groups: groups ?? const {},
      groupProperties: groupProperties ?? const {},
      disableGeoip: disableGeoip,
    );
    return result?.variant ?? result?.enabled ?? false;
  }

  Future<void> resetAdapterState() async {
    unawaited(_plugin?.close());
    _plugin = null;
    _client = null;
    await _proxy?.close();
    _proxy = null;
    _initialized = false;
    state = _AdapterState();
  }
}

class _AdapterState {
  int totalEventsCaptured = 0;
  int totalEventsSent = 0;
  int totalRetries = 0;
  String? lastError;
  final requestsMade = <_RequestRecord>[];
  final logLines = <String>[];

  Map<String, Object?> toJson({required int pendingEvents}) => {
        'pending_events': pendingEvents,
        'total_events_captured': totalEventsCaptured,
        'total_events_sent': totalEventsSent,
        'total_retries': totalRetries,
        'last_error': lastError,
        'requests_made':
            requestsMade.map((request) => request.toJson()).toList(),
        'log_lines': logLines,
      };
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

/// [properties] with a `$test_padding` string, starting with [marker], that
/// makes them exactly [bytes] long as compact UTF-8 JSON. Payloads that big
/// can't pass through the harness's request to the adapter.
Map<String, Object?> _padProperties(
  Map<String, Object?> properties,
  int bytes,
  String? marker,
) {
  final prefix = marker ?? '';
  final padded = {...properties, r'$test_padding': prefix};
  final missing = bytes - utf8.encode(jsonEncode(padded)).length;
  padded[r'$test_padding'] = prefix + 'x' * max(0, missing);
  return padded;
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
